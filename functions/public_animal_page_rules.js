// HTML for an animal's public web page (/animal/<id>), the link staff add
// to Facebook posts and shared links. Pure functions only, so the page can
// be tested without Firestore; functions/public_animal_page.js serves it.
//
// Built from publicAnimals/{id} (functions/public_animals.js), never from
// animals/{id}: only fields already meant for the public appear here. The
// page is rendered on the server because Facebook's link preview reads the
// og: tags without running scripts.

const APP_PACKAGE = 'com.dlsu.cap2507.respawnd1';
const APP_SCHEME = 'respawnd';
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

const isValidAnimalId = (id) => typeof id === 'string' && ID_PATTERN.test(id);

function escapeHtml(value) {
  return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
}

const isHttpUrl = (v) => typeof v === 'string' && /^https?:\/\//i.test(v);
const str = (v) => (typeof v === 'string' ? v.trim() : '');
const list = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string' && x.trim()).map((x) => x.trim()) : []);

/// Photo URL -> caption, from the stored `photoCaptions: [{url, caption}]`.
function captionsByUrl(raw) {
  const out = {};
  if (!Array.isArray(raw)) return out;
  for (const item of raw) {
    if (item && isHttpUrl(item.url) && str(item.caption)) out[item.url] = str(item.caption);
  }
  return out;
}

/// Plain-words status for the public, the same split the app's adoption
/// list uses (lib/features/adoption/adoption_page.dart _publicStatusLabel).
function statusLabel(animal) {
  if (animal.adoptionStatus === 'adopted') return 'Adopted';
  if (animal.adoptionStatus === 'reserved') return 'Reserved';
  if (animal.adoptionStatus === 'adoptable') return 'Available for adoption';
  return 'Not yet available';
}

function healthSummary(animal) {
  const out = [];
  if (animal.vaccinated === true) out.push('Vaccinated');
  if (animal.spayedNeutered === true) out.push('Spayed/Neutered');
  if (animal.dewormed === true) out.push('Dewormed');
  if (animal.specialNeeds === true) {
    const types = list(animal.specialNeedsTypes);
    out.push(types.length ? `Special needs: ${types.join(', ')}` : 'Special needs');
  }
  return out;
}

/// A JS string literal that is safe inside an inline <script>.
const jsString = (value) => JSON.stringify(String(value)).replace(/</g, '\\u003c');

function truncate(text, max) {
  const t = str(text).replace(/\s+/g, ' ');
  return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t;
}

/// Links that open this animal in the app: the custom scheme the app
/// registers (android/app/src/main/AndroidManifest.xml, ios Info.plist) and
/// an Android intent: URL that falls back to [pageUrl] when the app isn't
/// installed.
function appLinks(animalId, pageUrl) {
  const path = `open/animal/${animalId}`;
  const fallback = encodeURIComponent(`${pageUrl}?app=missing`);
  return {
    scheme: `${APP_SCHEME}://${path}`,
    androidIntent: `intent://${path}#Intent;scheme=${APP_SCHEME};package=${APP_PACKAGE};S.browser_fallback_url=${fallback};end`,
  };
}

const STYLES = `
  :root{--bg:#FBF9F4;--yellow:#FFD95E;--green:#C2B500;--tea:#E3E0B9;--text:#393207;--muted:#7E7D76;--surface:#FFFFFF;--line:#E9E5D6}
  @media (prefers-color-scheme:dark){:root{--bg:#1E1C15;--tea:#3A3729;--text:#F4F0DF;--muted:#B5B2A4;--surface:#2A2820;--line:#3D3A2E}}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);font-family:Zain,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;-webkit-font-smoothing:antialiased}
  .wrap{max-width:560px;margin:0 auto;padding:0 0 40px}
  .gallery{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;gap:0;background:var(--tea)}
  .gallery figure{flex:0 0 100%;margin:0;scroll-snap-align:start;position:relative}
  .gallery img{width:100%;height:340px;object-fit:cover;display:block}
  .gallery figcaption{position:absolute;left:0;right:0;bottom:0;padding:28px 16px 12px;color:#fff;font-size:16px;line-height:1.3;background:linear-gradient(transparent,rgba(0,0,0,.7))}
  .count{font-size:13px;color:var(--muted);text-align:center;margin:6px 0 0}
  .noimg{height:220px;display:flex;align-items:center;justify-content:center;background:var(--tea);font-size:64px}
  .body{padding:16px 20px}
  h1{font-family:"Tilt Warp",Zain,sans-serif;font-weight:400;font-size:30px;margin:8px 0 4px}
  .sub{color:var(--muted);font-size:17px;margin:0 0 12px}
  .chip{display:inline-block;background:var(--yellow);color:#393207;border-radius:999px;padding:4px 12px;font-size:14px;font-weight:700}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;margin:16px 0}
  .fact{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:10px 12px}
  .fact b{display:block;font-size:13px;color:var(--muted);font-weight:400}
  .fact span{font-size:17px;font-weight:700}
  h2{font-family:"Tilt Warp",Zain,sans-serif;font-weight:400;font-size:19px;margin:20px 0 6px}
  p.desc{font-size:17px;line-height:1.45;margin:0;white-space:pre-line}
  .tags{display:flex;flex-wrap:wrap;gap:6px}
  .tag{background:var(--surface);border:1px solid var(--line);border-radius:999px;padding:4px 10px;font-size:15px}
  .cta{display:block;text-align:center;text-decoration:none;background:var(--yellow);color:#393207;font-family:"Tilt Warp",Zain,sans-serif;font-size:18px;border-radius:30px;padding:14px 18px;margin:22px 0 8px}
  .note{font-size:14px;color:var(--muted);text-align:center;margin:0}
  .org{background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:14px;margin-top:20px}
  .org a{color:inherit}
  .org .links{display:flex;flex-wrap:wrap;gap:12px;margin-top:6px;font-size:16px}
  .center{min-height:80vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px}
  footer{text-align:center;color:var(--muted);font-size:13px;margin-top:28px}
`;

function head({title, description, imageUrl, pageUrl}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="ResPAWnd">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
${pageUrl ? `<meta property="og:url" content="${escapeHtml(pageUrl)}">` : ''}
${imageUrl ? `<meta property="og:image" content="${escapeHtml(imageUrl)}">` : ''}
<meta name="twitter:card" content="${imageUrl ? 'summary_large_image' : 'summary'}">
<link rel="icon" href="/favicon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Tilt+Warp&family=Zain:wght@400;700&display=swap" rel="stylesheet">
<style>${STYLES}</style>
</head>`;
}

/// The page for an animal that has no public profile (unknown id, archived,
/// hidden or deceased). Says nothing about why.
function buildNotFoundHtml() {
  return `${head({title: 'Animal not found — ResPAWnd', description: 'This animal profile is not available.'})}
<body><div class="wrap"><div class="center">
<div style="font-size:56px">🐾</div>
<h1>Profile not available</h1>
<p class="sub">This animal's profile was removed or isn't public any more.</p>
</div></div></body></html>`;
}

/// The full page for publicAnimals/{animalId}. [org] is the organization's
/// public profile fields (name, phone, email, facebookUrl, location), or null.
function buildAnimalPageHtml({animalId, animal, org, pageUrl}) {
  const name = str(animal.name) || str(animal.species) || 'This animal';
  const photos = list(animal.photoUrls).filter(isHttpUrl);
  const captions = captionsByUrl(animal.photoCaptions);
  const status = statusLabel(animal);
  const species = str(animal.species);
  const breed = str(animal.breed);
  const subtitle = [breed, species].filter(Boolean).join(' · ');
  const description = str(animal.description);
  const orgName = org ? str(org.name) : '';

  const ogDescription = truncate(
      [status, subtitle, description].filter(Boolean).join(' — ') ||
      `${name} is looking for a home${orgName ? ` with help from ${orgName}` : ''}.`,
      200,
  );

  const facts = [
    ['Sex', str(animal.sex)],
    ['Age', str(animal.age)],
    ['Size', str(animal.size)],
    ['Coat', str(animal.coatLength)],
  ].filter(([, v]) => v);

  const health = healthSummary(animal);
  const characteristics = list(animal.keyCharacteristics);
  const background = list(animal.rescueBackground);
  const links = appLinks(animalId, pageUrl);

  const gallery = photos.length ?
    `<div class="gallery" aria-label="Photos of ${escapeHtml(name)}">${photos.map((url, i) => `
      <figure><img src="${escapeHtml(url)}" alt="${escapeHtml(captions[url] || `${name}, photo ${i + 1}`)}" ${i ? 'loading="lazy"' : ''}>
      ${captions[url] ? `<figcaption>${escapeHtml(captions[url])}</figcaption>` : ''}</figure>`).join('')}
    </div>${photos.length > 1 ? `<p class="count">${photos.length} photos · swipe to see more</p>` : ''}` :
    '<div class="noimg" aria-hidden="true">🐾</div>';

  const orgBlock = org && orgName ? `
    <div class="org">
      <b>Cared for by ${escapeHtml(orgName)}</b>
      ${str(org.location) ? `<div class="sub" style="margin:2px 0 0">${escapeHtml(org.location)}</div>` : ''}
      <div class="links">
        ${str(org.phone) ? `<a href="tel:${escapeHtml(str(org.phone).replace(/[^\d+]/g, ''))}">Call</a>` : ''}
        ${str(org.email) ? `<a href="mailto:${escapeHtml(org.email)}">Email</a>` : ''}
        ${isHttpUrl(org.facebookUrl) ? `<a href="${escapeHtml(org.facebookUrl)}" rel="noopener">Facebook</a>` : ''}
      </div>
    </div>` : '';

  return `${head({title: `Meet ${name} — ResPAWnd`, description: ogDescription, imageUrl: photos[0], pageUrl})}
<body>
<div class="wrap">
  ${gallery}
  <div class="body">
    <span class="chip">${escapeHtml(status)}</span>
    <h1>${escapeHtml(name)}</h1>
    ${subtitle ? `<p class="sub">${escapeHtml(subtitle)}</p>` : ''}
    ${facts.length ? `<div class="grid">${facts.map(([k, v]) => `<div class="fact"><b>${k}</b><span>${escapeHtml(v)}</span></div>`).join('')}</div>` : ''}
    ${description ? `<h2>About ${escapeHtml(name)}</h2><p class="desc">${escapeHtml(description)}</p>` : ''}
    ${characteristics.length ? `<h2>Personality</h2><div class="tags">${characteristics.map((c) => `<span class="tag">${escapeHtml(c)}</span>`).join('')}</div>` : ''}
    ${health.length ? `<h2>Health</h2><div class="tags">${health.map((h) => `<span class="tag">${escapeHtml(h)}</span>`).join('')}</div>` : ''}
    ${background.length ? `<h2>Background</h2><div class="tags">${background.map((b) => `<span class="tag">${escapeHtml(b)}</span>`).join('')}</div>` : ''}
    <a class="cta" id="open-app" href="${escapeHtml(links.scheme)}">Open in the ResPAWnd app</a>
    <p class="note" id="app-note">Apply to adopt, sponsor or ask about ${escapeHtml(name)} in the app.</p>
    ${orgBlock}
    <footer>ResPAWnd</footer>
  </div>
</div>
<script>
(function () {
  var a = document.getElementById('open-app');
  if (/Android/i.test(navigator.userAgent)) a.href = ${jsString(links.androidIntent)};
  if (/[?&]app=missing/.test(location.search)) {
    document.getElementById('app-note').textContent = ${jsString(`The ResPAWnd app isn't installed on this phone. Ask ${orgName || 'the organization'} how to get it.`)};
  }
})();
</script>
</body>
</html>`;
}

module.exports = {
  APP_PACKAGE,
  APP_SCHEME,
  isValidAnimalId,
  escapeHtml,
  captionsByUrl,
  statusLabel,
  healthSummary,
  appLinks,
  buildAnimalPageHtml,
  buildNotFoundHtml,
};
