const SCRIPT = __GEOCHECK_SH__;

const REPO = "https://github.com/remnawave/geocheck";

function wantsShell(request) {
  const accept = request.headers.get("accept") || "";
  if (accept.includes("text/html")) return false;

  const ua = (request.headers.get("user-agent") || "").toLowerCase();
  return (
    ua.includes("curl") ||
    ua.includes("wget") ||
    ua.includes("fetch") ||
    ua.includes("libfetch") ||
    ua.includes("httpie") ||
    accept === "" ||
    accept === "*/*"
  );
}

function scriptResponse() {
  return new Response(SCRIPT, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=300",
      "x-content-type-options": "nosniff",
    },
  });
}

function htmlResponse() {
  const escaped = SCRIPT.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>geocheck.ing – run geocheck</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font: 15px/1.6 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    max-width: 46rem; margin: 3rem auto; padding: 0 1.25rem;
  }
  h1 { font-size: 1.4rem; margin-bottom: .25rem; }
  p.sub { opacity: .7; margin-top: 0; }
  pre {
    padding: .9rem 1rem; border-radius: .5rem; overflow-x: auto;
    background: rgba(127,127,127,.12);
  }
  code { background: rgba(127,127,127,.12); padding: .1rem .3rem; border-radius: .25rem; }
  .note { opacity: .75; font-size: .92rem; }
  a { color: inherit; }
</style>
</head>
<body>
<h1>geocheck</h1>
<p class="sub">Where the internet thinks you are, and how directly you reach it.</p>

<pre><code>curl -fsSL https://geocheck.ing | sh</code></pre>

<p>Pass flags after <code>-s --</code>:</p>
<pre><code>curl -fsSL https://geocheck.ing | sh -s -- -4 --detail</code></pre>

<p class="note">
Piping a remote script into a shell means trusting whatever this URL serves,
today and every day after. The whole script is below so you can read it first –
it is deliberately short. It runs an already-installed <code>geocheck</code> if
you have one, and otherwise runs the container image.
</p>

<pre><code>${escaped}</code></pre>

<p class="note">Source and releases: <a href="${REPO}">${REPO}</a></p>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
    },
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed\n", {
        status: 405,
        headers: { allow: "GET, HEAD", "content-type": "text/plain" },
      });
    }

    if (url.pathname === "/geocheck.sh" || url.pathname === "/install.sh") {
      return scriptResponse();
    }

    if (url.pathname !== "/") {
      return Response.redirect(new URL("/", url).toString(), 302);
    }

    return wantsShell(request) ? scriptResponse() : htmlResponse();
  },
};
