cat > x.html <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GTA 5</title>

  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    html, body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #000;
    }

    iframe {
      width: 100%;
      height: 100%;
      border: none;
      display: block;
    }
  </style>
</head>
<body>

  <iframe
    src="https://web.archive.org/web/20261005232456/https://playgta5.com/"
    title="GTA 5"
    allowfullscreen>
  </iframe>

</body>
</html>
EOF

cat > x.py <<'EOF'
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, quote, unquote, urlparse
from http.cookies import SimpleCookie
import ssl
import html
import re

HOST = "0.0.0.0"
PORT = 2000

START_URL = "file:///sec/root/x.html"

USER_AGENT = (
    "Mozilla/5.0 (Linux; Android 14; K) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/140.0.0.0 Mobile Safari/537.36"
)

ssl_context = ssl.create_default_context()

# Cookies separados por domínio
cookies = {}


def make_proxy_url(url):
    return "/proxy/" + quote(url, safe="")


def extract_proxy_url(path):
    prefix = "/proxy/"

    if not path.startswith(prefix):
        return None

    try:
        url = unquote(path[len(prefix):])

        if url.startswith(("http://", "https://")):
            return url
    except Exception:
        pass

    return None


def domain_of(url):
    return urlparse(url).netloc


def get_cookie_header(url):
    domain = domain_of(url)

    jar = cookies.get(domain, {})

    return "; ".join(
        f"{name}={value}"
        for name, value in jar.items()
    )


def save_cookies(url, headers):
    domain = domain_of(url)

    if domain not in cookies:
        cookies[domain] = {}

    try:
        values = headers.get_all("Set-Cookie", [])
    except Exception:
        values = []

    for value in values:
        try:
            c = SimpleCookie()
            c.load(value)

            for name, morsel in c.items():
                cookies[domain][name] = morsel.value

        except Exception:
            pass


def rewrite_resource_url(value, page_url):
    value = value.strip()

    if not value:
        return value

    # Não mexer nesses esquemas
    if value.startswith((
        "#",
        "javascript:",
        "data:",
        "blob:",
        "mailto:",
        "tel:"
    )):
        return value

    try:
        absolute = urljoin(page_url, value)
    except Exception:
        return value

    if absolute.startswith(("http://", "https://")):
        return make_proxy_url(absolute)

    return value


def rewrite_html(data, page_url):

    text = data.decode(
        "utf-8",
        errors="replace"
    )

    # Remove CSP que pode bloquear o proxy.
    text = re.sub(
        r"<meta\b[^>]*"
        r"http-equiv\s*=\s*['\"]"
        r"Content-Security-Policy"
        r"['\"][^>]*>",
        "",
        text,
        flags=re.I
    )

    # -------------------------------------------------
    # HREF
    # -------------------------------------------------

    def href_callback(match):

        before = match.group(1)
        quote_char = match.group(2)
        value = match.group(3)

        new_value = rewrite_resource_url(
            value,
            page_url
        )

        return (
            before +
            quote_char +
            html.escape(
                new_value,
                quote=True
            ) +
            quote_char
        )

    text = re.sub(
        r'(\bhref\s*=\s*)(["\'])(.*?)\2',
        href_callback,
        text,
        flags=re.I
    )

    # -------------------------------------------------
    # SRC
    # -------------------------------------------------

    def src_callback(match):

        before = match.group(1)
        quote_char = match.group(2)
        value = match.group(3)

        new_value = rewrite_resource_url(
            value,
            page_url
        )

        return (
            before +
            quote_char +
            html.escape(
                new_value,
                quote=True
            ) +
            quote_char
        )

    text = re.sub(
        r'(\bsrc\s*=\s*)(["\'])(.*?)\2',
        src_callback,
        text,
        flags=re.I
    )

    # -------------------------------------------------
    # ACTION
    # -------------------------------------------------

    def action_callback(match):

        before = match.group(1)
        quote_char = match.group(2)
        value = match.group(3)

        new_value = rewrite_resource_url(
            value,
            page_url
        )

        return (
            before +
            quote_char +
            html.escape(
                new_value,
                quote=True
            ) +
            quote_char
        )

    text = re.sub(
        r'(\baction\s*=\s*)(["\'])(.*?)\2',
        action_callback,
        text,
        flags=re.I
    )

    # -------------------------------------------------
    # SCRIPT
    # -------------------------------------------------

    injected_js = r"""
<script>
(function () {

    function toProxy(url) {

        try {

            const u =
                new URL(
                    url,
                    document.baseURI
                );

            if (
                u.protocol === "http:" ||
                u.protocol === "https:"
            ) {
                return "/proxy/" +
                    encodeURIComponent(
                        u.href
                    );
            }

        } catch (e) {}

        return url;
    }


    /*
     * Intercepta links criados
     * dinamicamente.
     */
    document.addEventListener(
        "click",
        function (event) {

            const link =
                event.target.closest("a");

            if (!link)
                return;

            const href =
                link.getAttribute("href");

            if (!href)
                return;

            if (
                href.startsWith("#") ||
                href.startsWith("javascript:") ||
                href.startsWith("mailto:") ||
                href.startsWith("tel:")
            )
                return;

            try {

                const target =
                    new URL(
                        href,
                        document.baseURI
                    );

                if (
                    target.protocol === "http:" ||
                    target.protocol === "https:"
                ) {

                    event.preventDefault();

                    location.href =
                        "/proxy/" +
                        encodeURIComponent(
                            target.href
                        );
                }

            } catch (e) {}

        },
        true
    );


    /*
     * window.open
     */
    const oldOpen =
        window.open;

    window.open =
        function(url, target, features) {

            if (url) {
                url = toProxy(url);
            }

            return oldOpen.call(
                window,
                url,
                target,
                features
            );
        };


})();
</script>
"""

    # Injeta antes do </head>
    if re.search(
        r"</head\s*>",
        text,
        flags=re.I
    ):

        text = re.sub(
            r"</head\s*>",
            injected_js + "</head>",
            text,
            count=1,
            flags=re.I
        )

    else:
        text = injected_js + text

    return text.encode("utf-8")


class Handler(BaseHTTPRequestHandler):

    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[HTTP]", fmt % args)

    def do_GET(self):
        self.proxy("GET")

    def do_POST(self):
        self.proxy("POST")

    def do_HEAD(self):
        self.proxy("HEAD")

    def proxy(self, method):

        target = extract_proxy_url(
            self.path
        )

        # Primeira página
        if target is None:

            if self.path == "/":
                target = START_URL
            else:
                self.send_error(
                    404,
                    "Página não encontrada"
                )
                return

        print()
        print("================================")
        print("URL:", target)
        print("================================")

        request_headers = {
            "User-Agent": USER_AGENT,

            "Accept":
                "text/html,application/xhtml+xml,"
                "application/xml;q=0.9,"
                "image/avif,image/webp,"
                "image/apng,*/*;q=0.8",

            "Accept-Language":
                "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7",

            # Impede compressão que dificultaria
            # a alteração do HTML.
            "Accept-Encoding":
                "identity",

            "Cache-Control":
                "no-cache"
        }

        cookie = get_cookie_header(target)

        if cookie:
            request_headers["Cookie"] = cookie

        body = None

        if method == "POST":

            try:
                length = int(
                    self.headers.get(
                        "Content-Length",
                        "0"
                    )
                )
            except Exception:
                length = 0

            body = self.rfile.read(length)

            content_type = self.headers.get(
                "Content-Type"
            )

            if content_type:
                request_headers[
                    "Content-Type"
                ] = content_type

        try:

            req = Request(
                target,
                data=body,
                headers=request_headers,
                method=method
            )

            response = urlopen(
                req,
                context=ssl_context,
                timeout=30
            )

            save_cookies(
                target,
                response.headers
            )

            data = response.read()

            content_type = response.headers.get(
                "Content-Type",
                "application/octet-stream"
            )

            # -----------------------------------------
            # SOMENTE HTML É MODIFICADO
            # -----------------------------------------

            is_html = (
                "text/html"
                in content_type.lower()
            )

            if is_html:

                data = rewrite_html(
                    data,
                    target
                )

                content_type = (
                    "text/html; charset=utf-8"
                )

            self.send_response(
                response.status
            )

            self.send_header(
                "Content-Type",
                content_type
            )

            self.send_header(
                "Content-Length",
                str(len(data))
            )

            self.send_header(
                "Cache-Control",
                "no-cache"
            )

            # Redirecionamentos:
            # transforma Location externo
            # em URL do proxy.
            location = response.headers.get(
                "Location"
            )

            if location:

                absolute = urljoin(
                    target,
                    location
                )

                if absolute.startswith(
                    ("http://", "https://")
                ):

                    self.send_header(
                        "Location",
                        make_proxy_url(
                            absolute
                        )
                    )

            self.end_headers()

            if method != "HEAD":
                self.wfile.write(data)

        except HTTPError as error:

            data = error.read()

            save_cookies(
                target,
                error.headers
            )

            self.send_response(
                error.code
            )

            content_type = error.headers.get(
                "Content-Type",
                "text/html; charset=utf-8"
            )

            self.send_header(
                "Content-Type",
                content_type
            )

            self.send_header(
                "Content-Length",
                str(len(data))
            )

            self.end_headers()

            if method != "HEAD":
                self.wfile.write(data)

        except (URLError, TimeoutError) as error:

            print(
                "[ERRO DE CONEXÃO]",
                error
            )

            self.send_error(
                502,
                "Erro ao conectar ao site"
            )

        except Exception as error:

            print(
                "[ERRO]",
                repr(error)
            )

            self.send_error(
                500,
                str(error)
            )


print(
    "===================================="
)

print(
    f"Proxy iniciado:"
    f" http://127.0.0.1:{PORT}"
)

print(
    "===================================="
)

server = ThreadingHTTPServer(
    (HOST, PORT),
    Handler
)

server.serve_forever()
EOF

python x.py
