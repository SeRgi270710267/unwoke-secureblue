(function () {
  const el = document.querySelector("[data-factory-stamp]");
  if (!el) return;

  function fmt(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (isNaN(d.getTime())) return iso;
    const mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()];
    const hh = String(d.getUTCHours()).padStart(2, "0");
    const mm = String(d.getUTCMinutes()).padStart(2, "0");
    return d.getUTCDate() + " " + mon + " " + hh + ":" + mm + " UTC";
  }

  function ghUrl(u) {
    try {
      const x = new URL(u);
      if (x.protocol === "https:" && x.hostname === "github.com") return x.href;
    } catch (e) { /* ignore */ }
    return "";
  }

  function tile(name, run, missing) {
    const li = document.createElement("li");
    const href = run && ghUrl(run.html_url || "");
    const inner = href ? document.createElement("a") : document.createElement("div");
    if (href) inner.href = href;
    inner.className = href ? "stamp-hit" : "stamp-dead";
    const lab = document.createElement("span");
    lab.className = "stamp-name";
    lab.textContent = name;
    const when = document.createElement("span");
    when.className = "stamp-when";
    when.textContent = run && run.updated_at ? fmt(run.updated_at) : missing;
    inner.appendChild(lab);
    inner.appendChild(when);
    li.appendChild(inner);
    return li;
  }

  function render(s) {
    el.textContent = "";
    el.classList.add("factory-stamp");
    const kicker = document.createElement("p");
    kicker.className = "stamp-kicker";
    kicker.textContent = "Last green";
    const ul = document.createElement("ul");
    ul.className = "stamp-grid";
    ul.appendChild(tile("Images", s && s.overlay, "No bake yet"));
    ul.appendChild(tile("Inspected", s && s.inspect, "No inspect yet"));
    ul.appendChild(tile("USB ISO", s && s.iso && s.iso.ok ? s.iso : null, "No ISO yet"));
    ul.appendChild(tile("Vendors", s && s.vendor && s.vendor.ok ? s.vendor : null, "No watch yet"));
    el.appendChild(kicker);
    el.appendChild(ul);
  }

  function fromApi() {
    const repo = "SeRgi270710267/unwoke-secureblue";
    const q = "https://api.github.com/repos/" + repo + "/actions/workflows/";
    return Promise.all([
      fetch(q + "build.yml/runs?status=success&per_page=1"),
      fetch(q + "verify.yml/runs?status=success&per_page=1"),
      fetch(q + "iso.yml/runs?status=success&per_page=1"),
      fetch(q + "vendor-watch.yml/runs?status=success&per_page=1"),
    ]).then(async (resps) => {
      async function first(r) {
        if (!r.ok) return null;
        const j = await r.json();
        const run = (j.workflow_runs || []).find((w) => w.conclusion === "success");
        return run
          ? { ok: true, updated_at: run.updated_at, html_url: run.html_url }
          : null;
      }
      return {
        overlay: await first(resps[0]),
        inspect: await first(resps[1]),
        iso: await first(resps[2]),
        vendor: await first(resps[3]),
      };
    });
  }

  fetch("status.json", { headers: { Accept: "application/json" } })
    .then((r) => {
      if (!r.ok) throw new Error("no status.json");
      return r.json();
    })
    .then(render)
    .catch(() => {
      fromApi()
        .then(render)
        .catch(() => {
          el.textContent = "Last green bake: could not load (offline or rate limit).";
        });
    });
})();
