package access

import (
	"context"
	"net/url"
	"regexp"
	"strings"

	"github.com/remnawave/geocheck/internal/netx"
)

const browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
	"(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"

// Checks returns the service-availability probes, in display order.
func Checks() []Check {
	return []Check{
		chatGPTWeb(),
		chatGPTApp(),
		youTubePremium(),
		netflix(),
		claude(),
		tiktok(),
	}
}

// youTubePremium confirms availability positively rather than by absence.
// The refusal sentence names the country; the "ad-free" wording only appears on
// the real offer page, so requiring it means a redirect to some other page
// cannot be mistaken for success.
func youTubePremium() Check {
	return Check{
		ID: "youtube_premium_access", Name: "YouTube Premium",
		Run: func(ctx context.Context, env Env) Result {
			resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
				URL:       "https://www.youtube.com/premium",
				UserAgent: browserUA,
				Headers:   map[string]string{"Accept-Language": "en-US,en;q=0.9"},
			})
			if err != nil {
				return Result{State: StateError, Detail: "request failed", Err: err}
			}

			body := strings.ToLower(resp.Text())
			switch {
			case strings.Contains(body, "youtube premium is not available in your country"):
				return Result{State: StateBlocked, Detail: "not offered in this country"}
			case strings.Contains(body, "ad-free"):
				return Result{State: StateAvailable}
			}
			return Result{
				State:  StateError,
				Detail: "neither the offer nor the refusal wording was present",
			}
		},
	}
}

// Netflix title IDs used to separate a full catalogue from an originals-only one.
//
// The first is a licensed third-party title, which Netflix only serves where it
// holds regional rights. The second is a Netflix original, available anywhere
// Netflix operates at all. Reaching the original but not the licensed title is
// the signature of an address Netflix serves in "originals only" mode, which is
// what it does for traffic it believes comes from a proxy or hosting provider.
const (
	netflixLicensedTitle = "70143836"
	netflixOriginalTitle = "80197526"
)

func netflix() Check {
	return Check{
		ID: "netflix_access", Name: "Netflix",
		Run: func(ctx context.Context, env Env) Result {
			region, ok, err := netflixTitle(ctx, env, netflixLicensedTitle)
			if err != nil {
				return Result{State: StateError, Detail: "request failed", Err: err}
			}
			if ok {
				return Result{
					State: StateAvailable, Region: region,
					Detail: "full catalogue",
				}
			}

			region, ok, err = netflixTitle(ctx, env, netflixOriginalTitle)
			if err != nil {
				return Result{State: StateError, Detail: "request failed", Err: err}
			}
			if ok {
				return Result{
					State: StateRestricted, Region: region,
					Detail: "originals only; licensed titles are withheld",
				}
			}
			return Result{State: StateBlocked, Detail: "not available"}
		},
	}
}

// netflixBase is the origin the title checks run against; tests point it at a
// local server.
const netflixBase = "https://www.netflix.com"

func netflixTitle(ctx context.Context, env Env, id string) (region string, ok bool, err error) {
	return netflixTitleAt(ctx, env, netflixBase, id)
}

// netflixTitleAt fetches a title page and reads the region out of where Netflix
// redirects. A locale prefix such as /fr-en/title/... names the catalogue being
// served; a bare /title/... means the US one.
func netflixTitleAt(ctx context.Context, env Env, base, id string) (region string, ok bool, err error) {
	resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
		URL:       base + "/title/" + id,
		UserAgent: browserUA,
	})
	if err != nil {
		return "", false, err
	}
	if resp.Status == 404 {
		// Netflix answers 404 for a title it will not serve here.
		return "", false, nil
	}
	if !resp.OK() {
		return "", false, nil
	}

	final := resp.FinalURL
	if final == "" {
		return "", false, nil
	}
	u, perr := url.Parse(final)
	if perr != nil {
		return "", false, nil
	}

	// Path is either /title/<id> or /<locale>/title/<id>.
	seg := strings.SplitN(strings.TrimPrefix(u.Path, "/"), "/", 2)
	if len(seg) == 0 || seg[0] == "" {
		return "", false, nil
	}
	if seg[0] == "title" {
		return "US", true, nil
	}
	// A locale looks like "fr-en"; the country is the part before the dash.
	locale, _, _ := strings.Cut(seg[0], "-")
	if len(locale) != 2 {
		return "", false, nil
	}
	return strings.ToUpper(locale), true, nil
}

// chatGPTWeb uses the endpoint the web client calls before showing the login
// form; it names an unsupported country outright.
func chatGPTWeb() Check {
	return Check{
		ID: "chatgpt_web", Name: "ChatGPT (web)",
		Run: func(ctx context.Context, env Env) Result {
			resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
				URL:       "https://api.openai.com/compliance/cookie_requirements",
				UserAgent: browserUA,
			})
			if err != nil {
				return Result{State: StateError, Detail: "request failed", Err: err}
			}
			if containsFold(resp.Text(), "unsupported_country") {
				return Result{State: StateBlocked, Detail: "unsupported country"}
			}
			return Result{State: StateAvailable}
		},
	}
}

// chatGPTApp probes the host the iOS app talks to, which rejects hosting and
// proxy address space specifically — a different gate from the country check.
func chatGPTApp() Check {
	return Check{
		ID: "chatgpt_app", Name: "ChatGPT (app)",
		Run: func(ctx context.Context, env Env) Result {
			resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
				URL:       "https://ios.chat.openai.com",
				UserAgent: browserUA,
			})
			if err != nil {
				return Result{State: StateError, Detail: "request failed", Err: err}
			}
			body := resp.Text()
			switch {
			case containsFold(body, "disallowed isp"):
				return Result{
					State:  StateBlocked,
					Detail: "disallowed ISP; the exit address is classed as hosting or proxy space",
				}
			case containsFold(body, "been blocked"):
				return Result{State: StateBlocked, Detail: "blocked"}
			}
			return Result{State: StateAvailable}
		},
	}
}

var reCFLoc = regexp.MustCompile(`loc=([A-Z]{2})`)

// claudeUnavailableMarkers are the strings the region-refusal page carries. The
// apostrophe appears both literally and HTML-escaped depending on how the page
// is rendered, so both forms are matched.
var claudeUnavailableMarkers = []string{
	"app unavailable in region",
	"/app-unavailable-in-region",
	"unfortunately, claude isn't available here.",
	"unfortunately, claude isn&apos;t available here.",
	"unfortunately, claude isn&#39;t available here.",
}

func claude() Check {
	return Check{
		ID: "claude_access", Name: "Claude",
		Run: func(ctx context.Context, env Env) Result {
			region := cloudflareLoc(ctx, env, "https://claude.ai/cdn-cgi/trace")

			resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
				URL:       "https://claude.ai/",
				UserAgent: browserUA,
				Headers: map[string]string{
					"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
				},
			})
			if err != nil {
				return Result{State: StateError, Region: region, Detail: "request failed", Err: err}
			}

			body := strings.ToLower(resp.Text())
			for _, marker := range claudeUnavailableMarkers {
				if strings.Contains(body, marker) {
					return Result{State: StateBlocked, Region: region, Detail: "not available in this region"}
				}
			}
			if resp.Status == 403 {
				// The refusal page was not present, so the 403 is ambiguous:
				// claude.ai sits behind Cloudflare, which also returns 403 to
				// clients it takes for bots. Say so rather than reporting a
				// region block that may not exist.
				return Result{
					State: StateBlocked, Region: region,
					Detail: "HTTP 403 without the region page; may be bot protection, not geography",
				}
			}
			if resp.Status >= 200 && resp.Status < 400 {
				return Result{State: StateAvailable, Region: region}
			}
			return Result{
				State: StateError, Region: region,
				Detail: "unexpected HTTP " + itoa(resp.Status),
			}
		},
	}
}

// tiktokBlockMarkers are the phrasings TikTok uses to refuse a region.
var tiktokBlockMarkers = []string{
	"service is currently unavailable in your region",
	"tiktok is not available in your country",
	"tiktok is unavailable in your country",
	"not available in your region",
}

func tiktok() Check {
	return Check{
		ID: "tiktok_access", Name: "TikTok",
		Run: func(ctx context.Context, env Env) Result {
			resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
				URL:       "https://www.tiktok.com/",
				UserAgent: browserUA,
				Headers: map[string]string{
					"Accept":          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
					"Accept-Language": "en-US,en;q=0.9",
				},
			})
			if err != nil {
				return Result{State: StateError, Detail: "request failed", Err: err}
			}

			body := strings.ToLower(resp.Text())
			for _, marker := range tiktokBlockMarkers {
				if strings.Contains(body, marker) {
					return Result{State: StateBlocked, Detail: "blocked by region"}
				}
			}
			if resp.Status >= 200 && resp.Status < 400 {
				return Result{State: StateAvailable}
			}
			return Result{State: StateError, Detail: "unexpected HTTP " + itoa(resp.Status)}
		},
	}
}

// cloudflareLoc reads the country from a Cloudflare /cdn-cgi/trace document.
// It is best effort: the availability verdict does not depend on it.
func cloudflareLoc(ctx context.Context, env Env, traceURL string) string {
	resp, err := env.Stack.Do(ctx, env.Family, netx.Request{
		URL:       traceURL,
		UserAgent: browserUA,
		Headers:   map[string]string{"Accept": "text/plain,*/*;q=0.8"},
	})
	if err != nil {
		return ""
	}
	if m := reCFLoc.FindStringSubmatch(resp.Text()); m != nil {
		return m[1]
	}
	return ""
}

func containsFold(haystack, needle string) bool {
	return strings.Contains(strings.ToLower(haystack), strings.ToLower(needle))
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [12]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
