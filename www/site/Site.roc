## Pure presentation for trusted, reviewed Markdown. No remote assets or
## JavaScript are required. Every page uses relative links so previews work
## both at a server root and under a repository Pages prefix.
Site :: [].{
	Page : { path : Str, title : Str, label : Str, description : Str }
	pages : List(Page)
	pages = [
		{ path: "index.html", title: "Time for real applications", label: "Overview", description: "Find availability, handle civil time and preserve the meaning of dates with roc-time." },
		{ path: "getting-started.html", title: "Run your first application", label: "Get started", description: "Install the pinned compiler, run a released example and choose your package dependencies." },
		{ path: "booking.html", title: "Find free booking windows", label: "Booking & coverage", description: "Turn timestamp inputs into useful availability without losing gaps or endpoint meaning." },
		{ path: "calendar-zones.html", title: "Work with dates and clock changes", label: "Calendars & zones", description: "Choose calendar arithmetic and interpret local time using explicit immutable zone rules." },
		{ path: "schedules.html", title: "Generate and exchange schedules", label: "Schedules", description: "Keep recurrence identity, COUNT and exceptions intact with bounded resumable queries." },
		{ path: "profiles.html", title: "Know the supported scope", label: "Profiles & limits", description: "Distinguish supported temporal profiles, precision limits and development-only features." },
		{ path: "api.html", title: "Find the right API", label: "API reference", description: "Navigate roc-time modules by the job you need to do, with version-specific reference links." },
		{ path: "versions.html", title: "Keep examples and versions together", label: "Versions", description: "Understand release candidates, compiler pins, package URLs and development compatibility." },
	]
	render = |url, body| {
		current = match pages.find_first(|page| "/${page.path}" == url) {
			Ok(page) => page
			Err(_) => return Err(UnknownPage(url))
		}
		links = pages.map(
			|page| {
				selected = if page.path == current.path {
					" aria-current=\"page\""
				} else {
					""
				}
				"<a href=\"${page.path}\"${selected}>${page.label}</a>"
			},
		)
		nav = Str.join_with(links, "")
		Ok(
			Str.join_with(
				[
					"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
					"<title>${current.title} · roc-time</title><meta name=\"description\" content=\"${current.description}\"><style>${css}</style></head><body>",
					"<a class=\"skip\" href=\"#content\">Skip to content</a><header class=\"masthead\"><a class=\"brand\" href=\"index.html\"><span class=\"mark\" aria-hidden=\"true\">[ ]</span> roc-time</a><span class=\"tagline\">Dates. Intervals. Clear choices.</span><a class=\"repo\" href=\"https://github.com/lukewilliamboswell/roc-time\">GitHub ↗</a></header>",
					"<div class=\"layout\"><aside><p class=\"eyebrow\">Documentation</p><nav aria-label=\"Documentation\">${nav}</nav><p class=\"release\">Released guide<br><strong>0.1.0-rc3</strong><br><a href=\"versions.html\">Compiler & package versions →</a></p></aside>",
					"<main id=\"content\"><p class=\"eyebrow\">roc-time / ${current.label}</p><article>${body}</article><footer>Built with <a href=\"https://github.com/lukewilliamboswell/basic-ssg\">basic-ssg</a> and Roc. <a href=\"https://github.com/lukewilliamboswell/roc-time/tree/main/www/site/content\">Improve these guides</a>.</footer></main></div></body></html>",
				],
				"",
			),
		)
	}
}

css : Str
css = Str.join_with(
	[
		":root{color-scheme:light;--ink:#173036;--muted:#52686b;--accent:#096b5a;--paper:#fbfcf8;--line:#dce5dd;--wash:#edf3e9}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.7 system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif}a{color:var(--accent);text-underline-offset:3px}a:hover{text-decoration-thickness:2px}a:focus-visible{outline:3px solid #dc9c27;outline-offset:4px}.skip{position:absolute;left:1rem;top:-8rem;background:white;padding:1rem;z-index:3}.skip:focus{top:1rem}",
		".masthead{max-width:1280px;margin:auto;padding:25px 40px;display:flex;align-items:center;gap:30px;border-bottom:1px solid var(--line)}.brand{font-size:25px;font-weight:750;letter-spacing:-1px;text-decoration:none;color:var(--ink)}.mark{color:var(--accent);letter-spacing:3px}.tagline{color:var(--muted);font-size:14px}.repo{margin-left:auto;font-size:14px}.layout{max-width:1280px;margin:auto;display:grid;grid-template-columns:255px minmax(0,1fr);gap:65px;padding:42px 40px 60px}aside{align-self:start;position:sticky;top:25px}.eyebrow{font:700 11px/1.5 system-ui;letter-spacing:2px;text-transform:uppercase;color:var(--muted);margin:0 0 18px}nav{display:grid;gap:4px}nav a{padding:9px 12px;border-radius:6px;text-decoration:none;color:var(--muted);font-size:15px}nav a:hover{background:var(--wash)}nav a[aria-current]{background:var(--wash);color:var(--accent);font-weight:700}.release{font-size:13px;line-height:1.8;border-top:1px solid var(--line);padding-top:25px;margin-top:30px;color:var(--muted)}.release strong{font-size:17px;color:var(--ink)}",
		"main{min-width:0;max-width:850px}h1{font-size:clamp(34px,4.8vw,58px);line-height:1.09;letter-spacing:-2px;margin:0 0 28px;max-width:760px}h2{font-size:26px;line-height:1.25;letter-spacing:-.6px;margin:44px 0 16px}h3{font-size:19px;margin:28px 0 12px}p{margin:0 0 20px}article>p:first-of-type{font-size:21px;line-height:1.6;color:var(--muted)}strong{font-weight:700}ul,ol{padding-left:24px}li{margin:8px 0}blockquote{margin:25px 0;padding:16px 22px;background:var(--wash);border-left:3px solid var(--accent)}blockquote p:last-child{margin-bottom:0}table{border-collapse:collapse;width:100%;font-size:15px;margin:24px 0}th,td{text-align:left;vertical-align:top;border-bottom:1px solid var(--line);padding:13px 10px}th{font-size:12px;text-transform:uppercase;letter-spacing:.6px;background:var(--wash)}code{font:14px/1.65 ui-monospace,SFMono-Regular,Consolas,monospace;background:var(--wash);border-radius:3px;padding:2px 5px}pre{padding:22px;background:#173036;color:#f1f7ee;border-radius:8px;overflow:auto;margin:25px 0}pre code{padding:0;background:none;color:inherit;white-space:pre}footer{border-top:1px solid var(--line);margin-top:55px;padding-top:24px;font-size:13px;color:var(--muted)}",
		"@media(max-width:850px){.layout{gap:25px;grid-template-columns:200px minmax(0,1fr);padding:30px 24px}.masthead{padding:20px 24px}.tagline{display:none}}@media(max-width:640px){.layout{display:block;padding:24px 20px}.masthead{padding:18px 20px}aside{position:static;border-bottom:1px solid var(--line);margin-bottom:30px;padding-bottom:20px}nav{grid-template-columns:1fr 1fr;gap:2px}nav a{font-size:14px;padding:7px}.release{margin:16px 0 0;padding-top:12px;font-size:12px}.release br{display:none}.release strong{font-size:12px;margin:0 10px}h1{letter-spacing:-1px}table{display:block;overflow:auto}article>p:first-of-type{font-size:19px}}@media(prefers-reduced-motion:no-preference){a{transition:background .12s ease,color .12s ease}}",
	],
	"",
)
