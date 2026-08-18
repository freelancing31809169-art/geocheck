package render

import (
	"bytes"
	"encoding/base64"
	"encoding/xml"
	"io"
	"regexp"
	"strings"
	"testing"
)

func demoSVG(t *testing.T) string {
	t.Helper()
	var buf bytes.Buffer
	if err := SVG(&buf, DemoReport("test"), nil); err != nil {
		t.Fatalf("SVG: %v", err)
	}
	return buf.String()
}

// TestSVGIsWellFormed catches the failure mode this renderer is most prone to:
// a stray character from the report reaching the markup unescaped and taking
// the whole document down. Hostnames and detail strings are attacker-adjacent
// text — they come from DNS and from HTTP bodies.
func TestSVGIsWellFormed(t *testing.T) {
	dec := xml.NewDecoder(strings.NewReader(demoSVG(t)))
	for {
		_, err := dec.Token()
		if err == io.EOF {
			return
		}
		if err != nil {
			t.Fatalf("the SVG is not well-formed XML: %v", err)
		}
	}
}

func TestSVGEscapesMarkup(t *testing.T) {
	r := DemoReport("test")
	// A plausible shape for a value that arrives from the network.
	r.Identity.Org = `Ex & Co <script>alert("x")</script>`

	var buf bytes.Buffer
	if err := SVG(&buf, r, nil); err != nil {
		t.Fatalf("SVG: %v", err)
	}
	out := buf.String()

	if strings.Contains(out, "<script>") {
		t.Error("markup from the report reached the document unescaped")
	}
	for _, want := range []string{"&amp;", "&lt;script&gt;"} {
		if !strings.Contains(out, want) {
			t.Errorf("expected %q in the output", want)
		}
	}

	dec := xml.NewDecoder(strings.NewReader(out))
	for {
		_, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("escaping produced invalid XML: %v", err)
		}
	}
}

// TestSVGIsSelfContained is the property that makes the output shareable: it
// must not reach out to the network when displayed. A picture that silently
// fetched a font would also report the viewer's address to whoever hosts it.
func TestSVGIsSelfContained(t *testing.T) {
	out := demoSVG(t)

	refs := regexp.MustCompile(`(?:xlink:href|href)="([^"]*)"|url\(([^)]*)\)`)
	for _, m := range refs.FindAllStringSubmatch(out, -1) {
		ref := m[1] + m[2]
		if strings.HasPrefix(ref, "data:") || strings.HasPrefix(ref, "#") {
			continue
		}
		t.Errorf("the document references something external: %q", ref)
	}

	if n := strings.Count(out, "@font-face"); n != 2 {
		t.Errorf("expected both weights embedded, found %d @font-face rules", n)
	}
	if !strings.Contains(out, "font-variant-ligatures:none") {
		t.Error("ligatures must be disabled; they rewrite -> and -- in a transcript")
	}
}

// TestSVGBase64RoundTrips keeps the base64 form honest: what decodes must be
// the document itself, not a truncated one. The encoder is buffered, so a
// missing Close would silently drop the tail.
func TestSVGBase64RoundTrips(t *testing.T) {
	want := demoSVG(t)

	var enc bytes.Buffer
	if err := SVGBase64(&enc, DemoReport("test"), nil); err != nil {
		t.Fatalf("SVGBase64: %v", err)
	}
	got, err := base64.StdEncoding.DecodeString(enc.String())
	if err != nil {
		t.Fatalf("output is not valid base64: %v", err)
	}
	if string(got) != want {
		t.Errorf("decoded %d bytes, want %d", len(got), len(want))
	}
	if strings.ContainsAny(enc.String(), "\n\r") {
		t.Error("the base64 should be one unwrapped line, so it can be pasted as a data: URI")
	}
}

// TestANSIParsing pins the escape handling, including the case that would be
// most visible if it broke: an unrecognised sequence must vanish rather than
// be drawn as literal text.
func TestANSIParsing(t *testing.T) {
	cases := []struct {
		name  string
		in    string
		text  string
		bold  bool
		color string
	}{
		{"plain text", "hello", "hello", false, "#e6e6e6"},
		{"truecolor", "\x1b[38;2;94;224;138mgreen\x1b[m", "green", false, "#5ee08a"},
		{"bold truecolor", "\x1b[1;38;2;177;156;255mtitle\x1b[m", "title", true, "#b19cff"},
		{"unknown sequence is dropped", "\x1b[999Xtext", "text", false, "#e6e6e6"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			lines := ansiLines(c.in)
			if len(lines) != 1 || len(lines[0].runs) == 0 {
				t.Fatalf("expected one line with runs, got %#v", lines)
			}
			run := lines[0].runs[len(lines[0].runs)-1]
			if run.text != c.text {
				t.Errorf("text = %q, want %q", run.text, c.text)
			}
			if run.bold != c.bold {
				t.Errorf("bold = %v, want %v", run.bold, c.bold)
			}
			if got := run.colour(); got != c.color {
				t.Errorf("colour = %s, want %s", got, c.color)
			}
		})
	}
}

// TestSVGColumnsSurviveWideContent guards the assumption the layout rests on:
// runs are placed by column, so the column a run reports must match where its
// text actually starts in the line.
func TestSVGColumnsAreConsecutive(t *testing.T) {
	lines := ansiLines("\x1b[38;2;1;2;3mab\x1b[m cd \x1b[1mef\x1b[m")
	if len(lines) != 1 {
		t.Fatalf("expected one line, got %d", len(lines))
	}
	col := 0
	for _, r := range lines[0].runs {
		if r.col != col {
			t.Errorf("run %q starts at column %d, want %d", r.text, r.col, col)
		}
		col += len([]rune(r.text))
	}
	if col != len("ab cd ef") {
		t.Errorf("line width = %d, want %d", col, len("ab cd ef"))
	}
}
