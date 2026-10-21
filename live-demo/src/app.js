(() => {
  'use strict';
  const D = window.LS_DATA;
  const C = window.LS_COPY;
  const $ = (s) => document.querySelector(s);
  const content = $('#app-content');
  const nav = $('#bottom-nav');
  const header = $('#detail-header');
  const overlay = $('#image-overlay');
  const scrollPositions = new Map();
  let language = 'zh';
  let lastRoute = '';
  let overlayReturnFocus = null;
  try { if (localStorage.getItem('linesight-language') === 'en') language = 'en'; } catch { /* Preferences remain available in memory. */ }

  const escape = (value) => String(value ?? '').replace(/[&<>"']/g, (ch) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[ch]));
  const text = (value) => typeof value === 'object' && value !== null ? value[language] : String(value ?? '');
  const t = (key, values = {}) => {
    const pair = C[key];
    if (!pair) throw new Error(`Missing copy: ${key}`);
    return pair[language === 'en' ? 1 : 0].replace(/\{(\w+)\}/g, (_, name) => escape(values[name] ?? ''));
  };
  const get = (collection, id) => D[collection].find((item) => item.id === id);
  const member = (id) => get('members', id);
  const recipe = (id) => get('recipes', id);
  const station = (id) => get('stations', id);
  const job = (id) => get('jobs', id);
  const record = (id) => get('records', id);
  const href = (route) => '#/' + route;
  const artwork = (art, edge = false) => `./assets/part-${art}${edge ? '-edge' : ''}.svg`;
  const completion = D.records.filter((r) => r.result !== 'pending');
  const passed = completion.filter((r) => r.result === 'pass');
  const review = D.records.filter((r) => r.result !== 'pass');
  const rate = ((passed.length / completion.length) * 100).toFixed(1);
  const dateLabel = (date = D.date) => new Intl.DateTimeFormat(language === 'en' ? 'en-GB' : 'zh-CN', { year:'numeric', month:'short', day:'numeric' }).format(new Date(date + 'T12:00:00'));
  const stamp = (time) => `${dateLabel()} · ${time}`;
  const paths = {
    home:'M3 10 12 3l9 7v10h-6v-7H9v7H3Z',
    records:'M8 4H5a2 2 0 0 0-2 2v14h18V6a2 2 0 0 0-2-2h-3M9 2h6v5H9ZM7 13l2 2 4-4m2 3h3m-11 4h11',
    recipes:'m12 3 10 5-10 5L2 8Zm-9 9 9 5 9-5M3 17l9 5 9-5',
    me:'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM4 21v-2a8 7 0 0 1 16 0v2',
    bell:'M5 17h14l-2-3V9a5 5 0 0 0-10 0v5Zm5 4h4',
    scan:'M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M2 12h20M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
    check:'M5 12l4 4L19 6',
    verified:'m12 2 3 2 4 1 1 4 2 3-2 3-1 4-4 1-3 2-3-2-4-1-1-4-2-3 2-3 1-4 4-1Zm-5 10 3 3 7-7',
    alert:'m12 3 10 18H2Zm0 6v5m0 3v.1',
    arrow:'M5 12h14m-5-5 5 5-5 5',
    right:'m9 5 7 7-7 7', left:'m15 5-7 7 7 7',
    jobs:'m12 3 9 5v11l-9 4-9-4V8Zm-9 5 9 5 9-5m-9 5v10M7 5l9 5',
    team:'M14 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM2 21v-3a7 6 0 0 1 14 0v3M18 4a3 3 0 0 1 0 6m2 11v-3a6 6 0 0 0-3-5',
    printer:'M6 8V2h12v6M6 17H3V8h18v9h-3M6 13h12v9H6Zm11-2h1',
    chart:'M3 3v18h18M7 15l4-5 4 3 5-8m-5 0h5v5',
    clock:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-5v5l4 3',
    image:'M3 3h18v18H3Zm0 14 6-6 5 5 3-3 4 4M16 7h.01',
    expand:'M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5',
    close:'m6 6 12 12M18 6 6 18',
    guide:'M12 5C8 2 4 2 2 3v16c3-1 7-1 10 2m0-16c4-3 8-3 10-2v16c-3-1-7-1-10 2Zm-6 3h3m6 0h3M6 12h3m6 0h3',
    language:'M2 5h13M9 2v3M4 8c2 5 5 8 9 10M13 5c-1 6-5 11-10 14M14 22l5-13 5 13m-8-5h6',
    settings:'M4 6h16M4 12h16M4 18h16M8 3v6m8 0v6m-6 0v6',
    folder:'M2 7V4h8l2 3h10v14H2Z',
    shield:'m12 2 9 4v6c0 6-9 10-9 10S3 18 3 12V6Zm-4 10 3 3 5-6',
    layers:'m12 3 9 5-9 5-9-5Zm-9 9 9 5 9-5M3 17l9 5 9-5'
  };
  const icon = (name, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.scan}"/></svg>`;
  const square = (name, color = '') => `<span class="square-icon ${color}">${icon(name)}</span>`;
  const chevron = () => icon('right', 'chevron');
  const pill = (label, color = '', dot = false) => `<span class="pill ${color}">${dot ? '<i class="dot"></i>' : ''}${label}</span>`;
  const statusColor = (status) => ({ closed:'green', pass:'green', exception:'rose', issue:'rose', pending:'amber', queued:'neutral' }[status] || '');
  const status = (value, dot = false) => pill(t(value), statusColor(value), dot);
  const avatar = (person, large = false) => `<span class="avatar ${person.color}${large ? ' large' : ''}" aria-hidden="true">${escape(text(person.initials))}</span>`;
  const button = (route, label, glyph = 'arrow', cls = '') => `<a class="button ${cls}" href="${href(route)}">${glyph ? icon(glyph) : ''}${label}</a>`;
  const section = (title, route = '', label = t('viewAll')) => `<div class="section-heading"><h3>${title}</h3>${route ? `<a href="${href(route)}">${label}${chevron()}</a>` : ''}</div>`;
  const info = (label, value) => `<div class="info-row"><dt>${label}</dt><dd>${value}</dd></div>`;
  const infoCard = (title, rows, glyph = 'records') => `<section class="card"><h3 class="card-caption">${title}${icon(glyph)}</h3><dl class="info-list">${rows.join('')}</dl></section>`;
  const heading = (eyebrow, title, subtitle, action = '') => `<div class="page-heading"><div><p class="eyebrow">${eyebrow}</p><h2 tabindex="-1">${title}</h2>${subtitle ? `<p class="subline">${subtitle}</p>` : ''}</div>${action}</div>`;
  const pageIntro = (eyebrow, title, description = '') => `<p class="detail-label">${eyebrow}</p><h3 class="detail-title">${title}</h3>${description ? `<p class="detail-description">${description}</p>` : ''}`;
  const listRow = (route, glyph, title, subtitle = '', tail = '', color = '') => `<a class="list-row" href="${href(route)}">${square(glyph, color)}<div><strong>${title}</strong>${subtitle ? `<small>${subtitle}</small>` : ''}</div>${tail || chevron()}</a>`;
  const artPanel = (item, badge = '') => `<div class="art-panel"><img src="${artwork(item.art)}" alt="${escape(text(item.name))}">${badge ? `<span class="art-badge">${badge}</span>` : ''}<span class="art-number">LINE / SIGHT</span></div>`;
  const tabs = (items) => `<div class="segments">${items.map((item) => `<a href="${href(item.route)}" class="${item.active ? 'selected' : ''}" ${item.active ? 'aria-current="page"' : ''}>${item.label}</a>`).join('')}</div>`;
  const metricCards = () => `<div class="metrics"><a href="${href('records')}" class="metric">${icon('scan')}<strong>${completion.length}</strong><span>${t('todayInspections')}</span></a><a href="${href('insights')}" class="metric">${icon('verified')}<strong>${rate}<small>%</small></strong><span>${t('passRate')}</span></a><a href="${href('records?filter=review')}" class="metric">${icon('alert')}<strong>${review.length}</strong><span>${t('pendingReview')}</span></a></div>`;

  function stationCard(s) {
    const r = recipe(s.recipe);
    return `<a class="card card-link" href="${href(`stations/${s.id}`)}"><div class="station-top">${square('printer')}<div><h4>${escape(text(s.name))}</h4><p>${escape(s.printer)}</p></div>${status(s.status, true)}</div><div class="station-bottom"><span>${t('recipe')} <b>${escape(text(r.name))}</b></span><span>${r.version} ${chevron().replace('class="icon chevron"', 'class="icon chevron" style="display:inline-block;vertical-align:middle;width:10px;height:10px"')}</span></div></a>`;
  }
  function recordCard(r) {
    return `<a class="card card-link record-card" href="${href(`records/${r.id}`)}"><img class="part-thumb" src="${artwork(r.art)}" alt=""><div class="record-info"><h4>${escape(text(r.name))}</h4><p>LS-${r.id} · ${escape(text(station(r.station).name))}</p><div class="record-meta">${status(r.result)}<time>${r.time}</time></div></div>${chevron()}</a>`;
  }
  function jobCard(j) {
    return `<a class="card card-link job-card" href="${href(`jobs/${j.id}`)}"><div class="card-caption"><span class="detail-label" style="margin:0">JOB-${j.id}</span>${status(j.status, true)}</div><h4>${escape(text(j.name))}</h4><p class="job-info"><span>${escape(station(j.station).printer)}</span><span>·</span><span>${t('pieces', {count:j.quantity})}</span></p><div class="job-progress ${statusColor(j.status)}"><span style="width:${j.progress}%"></span></div><div class="job-footer"><span>${icon('me')}${escape(text(member(j.owner).name))}<span>·</span>${t('due')} ${j.due}</span><b>${t('viewJob')} →</b></div></a>`;
  }
  function recipeCard(r) {
    return `<a class="card card-link recipe-card" href="${href(`recipes/${r.id}`)}"><div class="recipe-card-top">${square('layers')}${pill(r.version, 'green')}</div><h4>${escape(text(r.name))}</h4><p>${r.material} · ${t('linkedStationCount',{count:D.stations.filter(s=>s.recipe===r.id).length})}</p><div class="recipe-stats"><div>${t('sensitivity')}<strong>${r.sensitivity}%</strong></div><div>${t('confidence')}<strong>${r.confidence}%</strong></div></div><div class="recipe-tags">${r.defects.map(d=>pill(escape(text(d)), 'neutral')).join('')}</div></a>`;
  }
  function memberRow(m) {
    return `<a class="list-row member-row" href="${href(`members/${m.id}`)}">${avatar(m)}<div><strong>${escape(text(m.name))}</strong><small>${escape(text(m.department))}</small></div>${pill(t('role_' + m.role), m.color === 'green' || m.role === 'owner' ? 'green' : 'neutral')}${chevron()}</a>`;
  }
  function homePage() {
    const greeting = t('greeting', {name:text(member('lin').name)});
    return heading(t('homeEyebrow'),t('homeTitle'),t('homeSubtitle',{greeting}),`<a class="icon-button" href="${href('notifications')}" aria-label="${t('notifications')}">${icon('bell')}<i class="notification-dot"></i></a>`)
      + `<section class="card hero-card"><div class="hero-top"><div>${pill(t('qualityTogether'),'green',true)}<h3 style="margin-top:14px">${t('heroTitle',{count:D.stations.length})}</h3><p>${t('heroDescription')}</p></div><img class="hero-mark" src="./assets/linesight-mark.svg" alt="" width="48" height="48"></div><div class="hero-actions">${button('stations/01',t('enterStation'),'scan')}${button('insights',t('insights'),'chart','secondary')}</div></section>`
      + metricCards()
      + `<div class="quick-links"><a class="card card-link quick-card" href="${href('jobs')}">${square('jobs')}<div><strong>${t('jobs')}</strong><small>${t('jobSubtitle')}</small></div></a><a class="card card-link quick-card" href="${href('team')}">${square('team','green')}<div><strong>${t('teamShort')}</strong><small>${t('teamSubtitle')}</small></div></a></div>`
      + section(t('stations'),'recipes?tab=stations') + D.stations.map(stationCard).join('')
      + section(t('latestRecords'),'records') + D.records.slice(0,3).map(recordCard).join('');
  }
  function recordsPage(params) {
    const filter = params.get('filter') || 'all';
    const items = D.records.filter(r=>filter==='pass'?r.result==='pass':filter==='review'?r.result!=='pass':true);
    return heading(t('recordsEyebrow'),t('recordsTitle'),t('recordsDescription'))
      + tabs([{route:'records',label:t('recordsAll'),active:filter==='all'},{route:'records?filter=pass',label:t('recordsPass'),active:filter==='pass'},{route:'records?filter=review',label:t('recordsReview'),active:filter==='review'}])
      + `<div class="job-count"><span>${dateLabel()}</span><span style="margin-left:auto">${t('recordsCount',{count:items.length})}</span></div>`
      + items.map(recordCard).join('');
  }
  function recordPage(r) {
    return `<div class="detail-title-row"><div><p class="detail-label">LS-${r.id}</p><h3 class="detail-title">${escape(text(r.name))}</h3></div>${status(r.result)}</div>`
      + artPanel(r)
      + infoCard(t('inspectionReference'),[info(t('inspectionTime'),stamp(r.time)),info(t('station'),escape(text(station(r.station).name))),info(t('recipe'),`${escape(text(recipe(r.recipe).name))} · ${recipe(r.recipe).version}`),info(t('reviewer'),escape(text(member(r.reviewer).name))),info(t('checks'),t('passedChecks'))])
      + `<section class="card"><h3 class="card-caption">${t('conclusion')}${icon(r.result==='pass'?'verified':r.result==='issue'?'alert':'clock')}</h3>${pill(t(r.result==='pass'?'passedConclusion':r.result==='issue'?'issueConclusion':'pendingConclusion'),statusColor(r.result))}<p class="small-note" style="margin-top:12px">${escape(text(r.note))}</p>${button(`evidence/${r.id}`,t('viewEvidence'),'image','full secondary')}</section>`
      + `<div class="card list-group">${listRow(`jobs/${r.job}`,'jobs',t('jobReference'),`JOB-${r.job} · ${escape(text(job(r.job).name))}`)}${r.result==='issue'?listRow('issues/1043','alert',t('viewIssue'),t('issueTitle'),'','rose'):''}</div>`;
  }
  function jobsPage(params) {
    const filter = params.get('filter') || 'all';
    const active = D.jobs.filter(j=>j.status!=='closed');
    const list = filter==='closed' ? D.jobs.filter(j=>j.status==='closed') : filter==='active' ? active : D.jobs;
    return pageIntro(t('jobsEyebrow'),t('jobsTitle'),t('jobsDescription'))
      + tabs([{route:'jobs',label:t('all'),active:filter==='all'},{route:'jobs?filter=active',label:t('activeJobs',{count:active.length}),active:filter==='active'},{route:'jobs?filter=closed',label:t('jobsCompleted'),active:filter==='closed'}])
      + list.map(jobCard).join('');
  }
  function workflow(j) {
    const stage = ({queued:0,printing:1,inspection:2,exception:2,closed:3})[j.status];
    return `<div class="steps">${['preparation','productionStep','qualityStep','completedStep'].map((label,i)=>`<div class="step ${i<stage?'done':i===stage?'active':''}"><span>${i<stage?icon('check'):i+1}</span>${t(label)}</div>`).join('')}</div>`;
  }
  function jobPage(j) {
    const r = recipe(j.recipe);
    const timeline = [{title:t('jobCreatedEvent'),description:`${text(member('lin').name)} · ${text(r.name)} ${r.version}`,time:j.created}];
    if(j.status!=='queued') timeline.push({title:t('jobPrintingEvent'),description:station(j.station).printer,time:j.created==='07:45'?'07:50':j.created==='08:00'?'08:05':'08:50'});
    if(['inspection','exception','closed'].includes(j.status)) timeline.push({title:t('jobInspectionEvent'),description:t('nextReview'),time:j.record?record(j.record).time:'09:28'});
    if(j.status==='closed') timeline.push({title:t('jobClosedEvent'),description:text(j.note),time:'09:30'});
    return `<div class="detail-title-row"><div><p class="detail-label">JOB-${j.id}</p><h3 class="detail-title">${escape(text(j.name))}</h3></div>${status(j.status)}</div>`
      + artPanel(j,pill(t('pieces',{count:j.quantity}),'neutral'))
      + `<section class="card">${workflow(j)}<p class="small-note">${escape(text(j.note))}</p>${j.record?button(`records/${j.record}`,t('viewQuality'),'records','full'):button(`stations/${j.station}`,t('viewStation'),'printer','full secondary')}${j.status==='exception'?button(`issues/${j.id}`,t('viewIssue'),'alert','full secondary'):''}</section>`
      + infoCard(t('jobInfo'),[info(t('quantity'),t('pieces',{count:j.quantity})),info(t('printer'),escape(station(j.station).printer)),info(t('recipe'),`${escape(text(r.name))} · ${r.version}`),info(t('owner'),`<a class="text-link" href="${href(`members/${j.owner}`)}">${escape(text(member(j.owner).name))}</a>`),info(t('due'),stamp(j.due))],'jobs')
      + `<section class="card"><h3 class="card-caption">${t('workflow')}${icon('clock')}</h3><ol class="timeline">${timeline.map((event,i)=>`<li class="${i===timeline.length-1?'current':'done'}"><strong>${event.title}</strong><p>${escape(event.description)}</p><time>${event.time}</time></li>`).join('')}</ol></section>`
      + `<div class="card list-group">${listRow(`recipes/${r.id}`,'recipes',t('relatedRecipe'),`${escape(text(r.name))} · ${r.version}`)}</div>`;
  }
  function issuePage() {
    return pageIntro('JOB-1043 · LS-2042',t('issueTitle'),t('issueDescription'))
      + artPanel(job('1043'),status('exception'))
      + `<section class="card issue-summary"><h3 class="card-caption">${t('issueSummary')}${icon('alert')}</h3><p>${t('issueRequirements')}</p></section>`
      + infoCard(t('taskAssigned'),[info(t('owner'),`<a class="text-link" href="${href('members/zhou')}">${escape(text(member('zhou').name))}</a>`),info(t('reviewer'),escape(text(member('chen').name))),info(t('due'),stamp('10:30'))],'team')
      + `<section class="card"><h3 class="card-caption">${t('workflow')}${icon('clock')}</h3><ol class="timeline"><li class="done"><strong>${t('issueFound')}</strong><p>${t('issueFoundNote')}</p><time>09:34</time></li><li class="current"><strong>${t('issueAssigned')}</strong><p>${t('issueAssignedNote')}</p><time>09:36</time></li><li><strong>${t('issueRecheck')}</strong><p>${t('issueRecheckNote')}</p></li></ol></section>`
      + `<div class="card list-group">${listRow('evidence/2042','image',t('viewEvidence'),`LS-2042 · ${t('imageSet')}`)}${listRow('jobs/1043','jobs',t('jobReference'),escape(text(job('1043').name)))}</div>`;
  }
  function stationPage(s) {
    const r = recipe(s.recipe); const j = job(s.job);
    return pageIntro(t('stationDetail'),escape(text(s.name)),escape(s.printer))
      + artPanel(j,status(s.status,true))
      + infoCard(t('configuration'),[info(t('printer'),escape(s.printer)),info(t('material'),s.material),info(t('owner'),escape(text(member(s.operator).name))),info(t('activeRecipe'),`${escape(text(r.name))} ${r.version}`)],'settings')
      + section(t('currentJob')) + jobCard(j)
      + `<div class="card list-group">${listRow(`recipes/${r.id}`,'recipes',t('viewRecipe'),t('recipeParameters'))}${listRow(`members/${s.operator}`,'me',t('owner'),escape(text(member(s.operator).name)))}</div>`;
  }
  function recipesPage(params) {
    const stationsTab = params.get('tab')==='stations';
    return heading(t('recipesEyebrow'),t('recipesTitle'),t('recipesDescription'))
      + tabs([{route:'recipes',label:t('recipeTab'),active:!stationsTab},{route:'recipes?tab=stations',label:t('stationTab'),active:stationsTab}])
      + (stationsTab?D.stations.map(stationCard).join(''):D.recipes.map(recipeCard).join(''));
  }
  function recipePage(r) {
    return pageIntro(`${r.material} · ${r.version}`,escape(text(r.name)),escape(text(r.description)))
      + infoCard(t('recipeParameters'),[info(t('recipeVersion'),r.version),info(t('material'),r.material),info(t('layer'),`${r.layer} mm`),info(t('nozzle'),`${r.nozzle} mm`),info(t('temperature'),`${r.temperature} °C`),info(t('sensitivity'),`${r.sensitivity}%`),info(t('confidence'),`${r.confidence}%`)],'settings')
      + `<section class="card"><h3 class="card-caption">${t('defectClasses')}${icon('scan')}</h3><div class="recipe-tags">${r.defects.map(d=>pill(escape(text(d)),'neutral')).join('')}</div></section>`
      + section(t('linkedStations')) + D.stations.filter(s=>s.recipe===r.id).map(stationCard).join('')
      + `<p class="page-footnote">${t('updated')} · ${dateLabel(r.updated)}</p>`;
  }
  function insightsPage(params) {
    const weekly=params.get('range')==='week';
    const rates=[94.1,96.2,93.8,97.1,95.5,96.7,Number(rate)];
    const points=rates.map((v,i)=>`${18+i*45},${116-(v-88)*7}`).join(' ');
    const dates=Array.from({length:7},(_,i)=>`${15+i}`);
    return pageIntro(t('insightsEyebrow'),t('insightsTitle'),t('insightsDescription'))
      + tabs([{route:'insights',label:t('today'),active:!weekly},{route:'insights?range=week',label:t('week'),active:weekly}])
      + `<section class="card"><h3 class="card-caption">${t(weekly?'weeklyRate':'todayOverview')}${pill(t(weekly?'week':'today'),'green')}</h3><div class="split-summary"><div><div class="big-number">${weekly?'95.0':rate}<small>%</small></div><p class="small-note" style="margin-top:8px">${t('passRate')}</p></div><div style="text-align:right"><strong style="font-size:17px">${weekly?'148':completion.length}</strong><p class="small-note" style="margin-top:6px">${t('inspectionVolume')}</p></div></div><svg class="chart" viewBox="0 0 306 154" role="img" aria-label="${t('weeklyRate')}">${[32,67,102].map(y=>`<path class="grid" d="M15 ${y}H294"/>`).join('')}<path d="M18 126 ${points.split(' ').map(p=>'L'+p.replace(',',' ')).join(' ')} L288 126Z" fill="#3478f6" opacity=".055"/><polyline points="${points}" fill="none" stroke="#3478f6" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>${rates.map((v,i)=>`<circle cx="${18+i*45}" cy="${116-(v-88)*7}" r="3" fill="white" stroke="#3478f6" stroke-width="1.5"/><text x="${18+i*45}" y="147" text-anchor="middle">10/${dates[i]}</text>`).join('')}</svg><div class="chart-legend"><span><i></i>${t('weeklyRate')}</span></div></section>`
      + `<section class="card"><h3 class="card-caption">${t('inspectionVolume')}${icon('chart')}</h3><div class="mini-bars">${[18,23,19,27,22,27,12].map((v,i)=>`<div class="mini-bar" style="height:${v/27*85}%"><span>10/${dates[i]}</span></div>`).join('')}</div></section>`
      + `<section class="card"><h3 class="card-caption">${t('issueBreakdown')}${pill('1','amber')}</h3>${['edgeBurr','holeOffset','surfaceScratch'].map((label,i)=>`<div class="defect-row"><span>${t(label)}</span><span class="defect-bar"><i style="width:${i===0?100:0}%"></i></span><strong>${i===0?'1':'0'}</strong></div>`).join('')}${button('records?filter=review',t('overviewLink'),'records','full secondary')}</section>`;
  }
  function teamPage() {
    return `<section class="card team-banner">${square('team','green')}<h3>${escape(text(D.workspace))}</h3><p>${t('teamDescription')}</p><div class="team-avatars">${D.members.map(m=>avatar(m)).join('')}<span>${t('memberCount',{count:D.members.length})}</span></div></section>`
      + `<div class="quick-links"><a class="card quick-card card-link" href="${href('jobs')}">${square('jobs')}<div><strong>${D.jobs.length} · ${t('sharedJobs')}</strong><small>${t('jobSubtitle')}</small></div></a><a class="card quick-card card-link" href="${href('records')}">${square('records','green')}<div><strong>${D.records.length} · ${t('sharedRecords')}</strong><small>${t('inspectionReference')}</small></div></a></div>`
      + section(t('teamMembers')) + `<div class="card list-group">${D.members.map(memberRow).join('')}</div>`
      + section(t('sharedJobs'),'jobs') + D.jobs.slice(0,3).map(jobCard).join('');
  }
  function memberPage(m) {
    const jobs=D.jobs.filter(j=>j.owner===m.id);
    return `<section class="card member-hero">${avatar(m,true)}<h3>${escape(text(m.name))}</h3>${pill(t('role_'+m.role),m.role==='owner'?'green':'')}<p>${escape(text(m.title))}</p></section>`
      + infoCard(t('myProfile'),[info(t('workspace'),escape(text(D.workspace))),info(t('department'),escape(text(m.department))),info(t('teamRole'),t('role_'+m.role)),info(t('joined'),dateLabel(m.joined))],'me')
      + `<section class="card"><h3 class="card-caption">${t('responsibilities')}${icon('team')}</h3><p class="small-note">${t('responsibility_'+m.role)}</p></section>`
      + `<section class="card"><h3 class="card-caption">${t('permissionTitle')}${icon('shield')}</h3><p class="small-note">${t('permission_'+m.role)}</p></section>`
      + section(t('memberJobs')) + (jobs.length?jobs.map(jobCard).join(''):`<div class="card empty-state">${square('jobs')}<p>${t('noAssigned')}</p></div>`);
  }
  function mePage() {
    const m=member('lin');
    return heading(t('myEyebrow'),t('myTitle'),t('myDescription'))
      + `<a class="card profile-card card-link" href="${href('members/lin')}">${avatar(m)}<div><h3>${escape(text(m.name))}</h3><p>${escape(text(D.teamName))}</p>${pill(t('role_owner'),'green')}</div>${chevron()}</a>`
      + section(t('workspace')) + `<div class="card list-group">${listRow('team','team',t('team'),escape(text(D.workspace)),'','green')}${listRow('jobs','jobs',t('jobs'),t('jobSubtitle'))}${listRow('members/lin','me',t('myProfile'),t('myProfileSubtitle'))}</div>`
      + section(t('preferences')) + `<div class="card list-group"><button type="button" class="list-row" data-action="toggle-language" style="background:white;text-align:left;color:inherit">${square('language')}<div><strong>${t('language')}</strong><small>${t('languageDescription')}</small></div><span class="value">${language==='en'?'English':'中文'}</span>${chevron()}</button>${listRow('guide','guide',t('guide'),t('guideSubtitle'))}</div>`
      + `<p class="page-footnote">${t('pageFooter')}</p>`;
  }
  function guidePage() {
    return `<div class="guide-intro">${square('guide')}<h3>${t('guideTitle')}</h3><p>${t('guideIntro')}</p></div>`
      + [['guideOneTitle','guideOne','jobs','jobs'],['guideTwoTitle','guideTwo','records','records'],['guideThreeTitle','guideThree','team','viewTeam']].map(([title,body,route,label],i)=>`<section class="card guide-step"><span class="number">0${i+1}</span><div><h4>${t(title)}</h4><p>${t(body)}</p><a href="${href(route)}">${t(label)}${icon('arrow')}</a></div></section>`).join('');
  }
  function notificationsPage() {
    return `<p class="detail-description">${t('notificationsDescription')}</p>`
      + [['jobs/1041','notificationInspection','notificationInspectionText','09:41',''],['issues/1043','notificationIssue','notificationIssueText','09:36','issue'],['jobs/1044','notificationComplete','notificationCompleteText','09:30','success']].map(([route,title,body,time,cls])=>`<a class="card card-link notice-card ${cls}" href="${href(route)}"><h4>${t(title)}</h4><p>${t(body)}</p><time>${stamp(time)}</time></a>`).join('');
  }
  function evidencePage(r, params) {
    const view=params.get('view')||'compare';
    const types=view==='image'?[false]:view==='contour'?[true]:[false,true];
    return pageIntro(`LS-${r.id}`,escape(text(r.name)),t('evidenceDescription'))
      + tabs([{route:`evidence/${r.id}`,label:t('compare'),active:view==='compare'},{route:`evidence/${r.id}?view=image`,label:t('image'),active:view==='image'},{route:`evidence/${r.id}?view=contour`,label:t('contour'),active:view==='contour'}])
      + `<div class="evidence-pair ${types.length===1?'single':''}">${types.map(edge=>`<button type="button" class="evidence-tile" data-image="${r.id}" data-edge="${edge}" aria-label="${t('enlarge')} · ${t(edge?'contour':'image')}"><img src="${artwork(r.art,edge)}" alt="${escape(text(r.name))} · ${t(edge?'contour':'image')}"><span>${t(edge?'contour':'image')}${icon('expand')}</span></button>`).join('')}</div>`
      + infoCard(t('imageSet'),[info(t('reference'),`LS-${r.id}`),info(t('inspectionTime'),stamp(r.time)),info(t('station'),escape(text(station(r.station).name))),info(t('smallResult'),status(r.result))],'image')
      + `<div class="card list-group">${listRow(`records/${r.id}`,'records',t('recordDetail'),t('conclusion'))}${listRow(`jobs/${r.job}`,'jobs',t('jobReference'),`JOB-${r.job}`)}</div>`;
  }

  function routeDetails() {
    const raw=location.hash.replace(/^#\/?/,'')||'home';
    const q=raw.indexOf('?');
    const path=q<0?raw:raw.slice(0,q);
    const params=new URLSearchParams(q<0?'':raw.slice(q+1));
    const parts=path.split('/');
    const [name,id]=parts;
    if(parts.length>2 || (parts.length===2&&!id)) return null;
    if(['home','records','recipes','me'].includes(name)&&!id) return {path,params,tab:name,parent:'home',primary:true,title:t(name),body:()=>({home:homePage,records:()=>recordsPage(params),recipes:()=>recipesPage(params),me:mePage})[name]()};
    if(name==='jobs'&&!id) return {path,params,tab:'home',parent:'home',title:t('jobs'),body:()=>jobsPage(params)};
    if(name==='jobs'&&job(id)) return {path,params,tab:'home',parent:'jobs',title:t('jobDetail'),body:()=>jobPage(job(id))};
    if(name==='records'&&record(id)) return {path,params,tab:'records',parent:'records',title:t('recordDetail'),body:()=>recordPage(record(id))};
    if(name==='evidence'&&record(id)) return {path,params,tab:'records',parent:`records/${id}`,title:t('evidence'),body:()=>evidencePage(record(id),params)};
    if(name==='stations'&&station(id)) return {path,params,tab:'home',parent:'home',title:t('stationDetail'),body:()=>stationPage(station(id))};
    if(name==='recipes'&&recipe(id)) return {path,params,tab:'recipes',parent:'recipes',title:t('recipeDetail'),body:()=>recipePage(recipe(id))};
    if(name==='members'&&member(id)) return {path,params,tab:'me',parent:'team',title:t('memberDetail'),body:()=>memberPage(member(id))};
    if(name==='issues'&&id==='1043') return {path,params,tab:'home',parent:'jobs/1043',title:t('issueDetail'),body:issuePage};
    if(!id&&['insights','notifications','team','guide'].includes(name)) return {path,params,tab:['team','guide'].includes(name)?'me':'home',parent:name==='guide'?'me':'home',title:t(name),body:()=>({insights:()=>insightsPage(params),notifications:notificationsPage,team:teamPage,guide:guidePage})[name]()};
    return null;
  }
  function saveScroll() { if(lastRoute) scrollPositions.set(lastRoute,content.scrollTop); }
  function render({preserve=false,restore=false}={}) {
    const previousScroll=content.scrollTop;
    const route=routeDetails();
    if(!route) {
      history.replaceState({...history.state,lineSight:true},'','#/home');
      render();return;
    }
    closeImage(false);
    document.documentElement.lang=language==='en'?'en':'zh-CN';
    document.title=`LineSight · ${route.title}`;
    document.querySelector('meta[name=description]').content=language==='en'?'LineSight — Production, quality and handoffs in one clear view.':'LineSight — 从生产到质检，让每一件品质都有迹可循。';
    document.querySelectorAll('[data-copy]').forEach(node=>node.innerHTML=t(node.dataset.copy));
    $('#story-title').innerHTML=t('storyTitle');
    $('#story-links').innerHTML=[['jobs','jobs','production'],['records','scan','quality'],['team','team','collaboration']].map(([path,glyph,key])=>`<a href="${href(path)}">${icon(glyph)}${t(key)}</a>`).join('');
    $('#journey-line').innerHTML=['print','inspect','handoff'].map((key,i)=>`${i?'<i></i>':''}<span><b></b>${t(key)}</span>`).join('');
    $('#skip-link').textContent=t('skip');
    document.querySelectorAll('[data-language]').forEach(node=>node.setAttribute('aria-pressed',String(node.dataset.language===language)));
    nav.setAttribute('aria-label',t('navigation'));
    nav.innerHTML=['home','records','recipes','me'].map(key=>`<a href="${href(key)}" class="${route.tab===key?'active':''}" ${route.tab===key?'aria-current="page"':''}><span class="nav-icon">${icon(key)}</span><span>${t(key)}</span></a>`).join('');
    header.hidden=!!route.primary;
    header.innerHTML=route.primary?'':`<button class="icon-button" type="button" data-action="back" aria-label="${t('back')}">${icon('left')}</button><h2 tabindex="-1">${route.title}</h2><a class="icon-button" href="${href('home')}" aria-label="${t('returnHome')}">${icon('home')}</a>`;
    content.innerHTML=route.body();
    content.dataset.route=location.hash.replace(/^#\/?/,'');
    content.classList.remove('route-enter');
    void content.offsetWidth;
    content.classList.add('route-enter');
    content.scrollTop=preserve?previousScroll:restore?(scrollPositions.get(location.hash)||0):0;
    lastRoute=location.hash;
    if(!preserve) (header.hidden?content.querySelector('h2'):header.querySelector('h2'))?.focus({preventScroll:true});
  }
  function go(path) {
    const target=href(path);
    if(target===location.hash){content.scrollTo({top:0,behavior:'auto'});return;}
    saveScroll();
    const depth=(history.state?.lineSight?history.state.depth:0)||0;
    history.pushState({lineSight:true,depth:depth+1},'',target);
    render();
  }
  function goBack() {
    const route=routeDetails();
    if(history.state?.lineSight&&history.state.depth>0) history.back();
    else go(route?.parent||'home');
  }
  function changeLanguage(code) {
    if(!['zh','en'].includes(code)||code===language) return;
    language=code;
    try {localStorage.setItem('linesight-language',code);} catch { /* Session-only preference. */ }
    render({preserve:true});
  }
  function setImageInert(value) {
    [content,nav,header,$('.brand-story'),$('.language-picker')].forEach(node=>node.inert=value);
  }
  function openImage(id,edge) {
    const r=record(id);if(!r)return;
    overlayReturnFocus=document.activeElement;
    overlay.innerHTML=`<div class="overlay-top"><span>${t(edge?'contour':'image')}</span><button type="button" class="icon-button" data-action="close-image" aria-label="${t('close')}">${icon('close')}</button></div><img src="${artwork(r.art,edge)}" alt="${escape(text(r.name))} · ${t(edge?'contour':'image')}"><p>${t('imageCaption',{name:text(r.name),id:r.id})}</p>`;
    overlay.setAttribute('role','dialog');overlay.setAttribute('aria-modal','true');overlay.setAttribute('aria-label',t(edge?'contour':'image'));
    overlay.hidden=false;setImageInert(true);
    overlay.querySelector('button').focus();
  }
  function closeImage(restoreFocus=true) {
    if(overlay.hidden)return;
    overlay.hidden=true;setImageInert(false);
    if(restoreFocus&&overlayReturnFocus?.isConnected)overlayReturnFocus.focus({preventScroll:true});
    overlayReturnFocus=null;
  }
  document.addEventListener('click',(event)=>{
    const element=event.target.closest('a,button');if(!element)return;
    if(element.dataset.language){changeLanguage(element.dataset.language);return;}
    if(element.dataset.image){openImage(element.dataset.image,element.dataset.edge==='true');return;}
    if(element.dataset.action==='back'){goBack();return;}
    if(element.dataset.action==='close-image'){closeImage();return;}
    if(element.dataset.action==='toggle-language'){changeLanguage(language==='zh'?'en':'zh');return;}
    const link=element.getAttribute('href');
    if(link?.startsWith('#/')&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey&&event.button===0){event.preventDefault();go(link.slice(2));}
  });
  document.addEventListener('keydown',event=>{
    if(overlay.hidden)return;
    if(event.key==='Escape'){event.preventDefault();closeImage();}
    if(event.key==='Tab'){event.preventDefault();overlay.querySelector('button').focus();}
  });
  window.addEventListener('popstate',()=>{saveScroll();render({restore:true});});
  window.addEventListener('hashchange',()=>{if(location.hash!==lastRoute){saveScroll();render({restore:true});}});
  try {history.replaceState({lineSight:true,depth:0},'',location.hash||'#/home');} catch { /* Browsers may restrict file history; hash routes still render. */ }
  render();
})();
