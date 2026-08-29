(function () {
  const el = document.querySelector("[data-factory-stamp]");
  if (!el) return;

  function fmt(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (isNaN(d.getTime())) return iso;
    return d.toISOString().slice(0, 16).replace("T", " ") + " UTC";
  }

  function ghUrl(u) {
    try {
      const x = new URL(u);
      if (x.protocol === "https:" && x.hostname === "github.com") return x.href;
    } catch (e) { /* ignore */ }
    return "";
  }

  function addLink(label, run) {
    if (!run || !run.updated_at) return;
    el.appendChild(document.createTextNode(label));
    const href = ghUrl(run.html_url || "");
    if (href) {
      const a = document.createElement("a");
      a.href = href;
      a.textContent = fmt(run.updated_at);
      el.appendChild(a);
    } else {
      el.appendChild(document.createTextNode(fmt(run.updated_at)));
    }
    el.appendChild(document.createTextNode(". "));
  }

  function render(s) {
    el.textContent = "";
    if (s && s.overlay && s.overlay.updated_at) {
      addLink("Images last green: ", s.overlay);
    } else {
      el.appendChild(document.createTextNode("Images last green: no successful bake listed. "));
    }
    if (s && s.inspect && s.inspect.updated_at) {
      addLink("Inspected: ", s.inspect);
    }
    if (s && s.iso && s.iso.ok && s.iso.updated_at) {
      addLink("USB ISO last green: ", s.iso);
    }
  }

  function fromApi() {
    const repo = "SeRgi270710267/unwoke-secureblue";
    const q = "https://api.github.com/repos/" + repo + "/actions/workflows/";
    return Promise.all([
      fetch(q + "build.yml/runs?status=success&per_page=1"),
      fetch(q + "verify.yml/runs?status=success&per_page=1"),
      fetch(q + "iso.yml/runs?status=success&per_page=1"),
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
