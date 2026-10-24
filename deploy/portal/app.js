 'use strict';
const $ = (selector) => document.querySelector(selector);
const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
const portal = $('#portal');
function fitPage() {
  const scale = Math.min(1, document.documentElement.clientWidth / 1190);
  portal.style.transform = `scale(${scale})`;
  $('#page-viewport').style.width = `${1190 * scale}px`;
  $('#page-viewport').style.height = `${2048 * scale}px`;
}
fitPage();
window.addEventListener('resize', fitPage, { passive: true });
const cards = [
  {
    "id": "workbench",
    "title": "质量工作台",
    "category": "工作台 / 一眼掌握",
    "caption": "工位、检测概览与异常入口",
    "detail": "常用功能集中在首屏：在线质检、扫码追溯、新建任务、质量报告与待办直达。",
    "image_type": "产品界面"
  },
  {
    "id": "jobs",
    "title": "生产任务",
    "category": "生产任务 / 进度有据",
    "caption": "待打印 → 打印中 → 待质检",
    "detail": "以任务状态串起生产交接；此操作记录进度，不向物理打印机下发指令。",
    "image_type": "产品界面"
  },
  {
    "id": "records",
    "title": "检测记录",
    "category": "检测记录 / 有迹可循",
    "caption": "筛选、查看、复核与归档",
    "detail": "按时间、工位与判定查看记录，原始结果与复核痕迹分别保留。",
    "image_type": "产品界面"
  },
  {
    "id": "evidence",
    "title": "照片与边缘参考",
    "category": "图片证据 / 看得明白",
    "caption": "原始照片 + 蓝色轮廓",
    "detail": "上传 PNG/JPEG 图片并查看边缘参考，质检结论由人确认。",
    "image_type": "产品界面"
  },
  {
    "id": "issues",
    "title": "异常处理",
    "category": "异常闭环 / 有人接手",
    "caption": "记录问题、指派成员、重新送检",
    "detail": "保留异常说明与处理意见，处理后可重新送检或关闭。",
    "image_type": "产品界面"
  },
  {
    "id": "team",
    "title": "团队工作区",
    "category": "团队协作 / 一起推进",
    "caption": "共享任务与成员角色",
    "detail": "团队管理员、主管、操作成员与只读成员分工协作；团队与普通用户使用同一登录入口。",
    "image_type": "产品界面"
  },
  {
    "id": "recipes",
    "title": "配方中心",
    "category": "配方配置 / 换型留痕",
    "caption": "配方、工位与配置版本",
    "detail": "管理检查参数、材料与缺陷类别；工位更换配方保留原因。",
    "image_type": "产品界面"
  },
  {
    "id": "insights",
    "title": "质量洞察",
    "category": "统计洞察 / 数字说话",
    "caption": "检测量、合格率与缺陷分布",
    "detail": "按范围查看统计并导出 PDF、打印或 CSV；报告包含逐项检查结果、影像、文档编号与 LineSight 团队签印。",
    "image_type": "产品界面"
  },
  {
    "id": "backup",
    "title": "数据管理",
    "category": "导出备份 / 留好副本",
    "caption": "CSV 导出 · 备份 · 恢复预览",
    "detail": "支持筛选导出、专业质量报告及备份恢复；作业文件提供外观检验指导书和换型核对表。",
    "image_type": "Android 历史界面，能力延续"
  },
  {
    "id": "bilingual",
    "title": "中英双语",
    "category": "语言切换 / 中文 EN",
    "caption": "中文与 English 界面",
    "detail": "工作区页面提供中英文切换；用户输入的名称和型号保持原内容。",
    "image_type": "产品界面"
  },
  {
    "id": "brand",
    "title": "粒子聚合开屏",
    "category": "1.1.20 / 新版到站",
    "caption": "四角吸附 · 扫描 · Logo 锁定",
    "detail": "2.8 秒品牌显现，期间并行准备本机数据与登录界面。",
    "image_type": "Android 1.1.20 正式构建录像关键帧"
  },
  {
    "id": "start",
    "title": "开始使用",
    "category": "下载中心 / Android",
    "caption": "安装 LineSight 1.1.58 · 内容版本 8",
    "detail": "首次安装选择正式版；已安装旧体验版请在下载中心选择兼容升级。安装后在工作台直接登录，账号由团队管理员提供。设置中默认使用大字版，可切换特供版。",
    "image_type": "统一登录 · 团队协作"
  }
];
cards.forEach((card,index) => {
  const article=document.createElement('article');
  article.className='gallery-card';
  article.id=card.id;
  const number=String(index+1).padStart(2,'0');
  article.innerHTML=`<header>${card.category}<span>${index===10?'新版发布':'产品界面'}</span></header><a class="gallery-image" href="${index===11?'assets/product/screen-12-content4.webp':`assets/product/screen-${number}.webp`}" aria-label="查看${card.title}"><img src="${index===11?'assets/product/screen-12-content4.webp':`assets/retro/poster-${number}.webp`}" alt="LineSight ${card.title}" decoding="async"></a><footer><p>${card.caption}</p><a class="view-image" href="${index===11?'assets/product/screen-12-content4.webp':`assets/product/screen-${number}.webp`}">↗ 查看功能与大图</a><button class="like" aria-label="收藏${card.title}" aria-pressed="false">☆ 收藏 <span>0</span></button></footer>`;
  article.querySelectorAll('.gallery-image,.view-image').forEach(link=>link.addEventListener('click',event=>{event.preventDefault();openCard(index);}));
  article.querySelector('.like').addEventListener('click',event=>{
    const button=event.currentTarget;
    const liked=button.getAttribute('aria-pressed')!=='true';
    button.setAttribute('aria-pressed',String(liked));
    button.innerHTML=`${liked?'★':'☆'} 收藏 <span>${liked?1:0}</span>`;
  });
  $('#gallery').append(article);
});

const stickerLabels=['新版到站','任务到哪了','图片证据','异常处理','团队一起干','质量看得见','现在就开工','BOJI推荐','记录别丢了','人工复核','LineSight'];
window.assetsReady=fetch('assets/assets-manifest.json').then(response=>{
  if(!response.ok) throw new Error('素材清单载入失败');
  return response.json();
}).then(({assets})=>{
  let stickerIndex=0;
  Object.entries(assets).forEach(([name,asset])=>{
    let element;
    if(name.startsWith('sticker-')){
      element=document.createElement('a');
      element.className='sticker';
      element.href=`#${cards[stickerIndex % cards.length].id}`;
      element.title='LineSight · '+stickerLabels[stickerIndex];
      const img=document.createElement('img');
      img.src=`assets/retro/${name}.png`;img.alt=element.title;
      element.append(img);$('#stickers').append(element);stickerIndex++;
    }else if(name.startsWith('side-')){
      const [,side,number]=name.split('-');element=$(`.${side}-${Number(number)}`);
    }else if(name.startsWith('float-'))element=$(`.${name}`);
    if(element)Object.assign(element.style,{left:`${asset.x}px`,top:`${asset.y}px`,width:`${asset.width}px`,height:`${asset.height}px`});
  });
  window.retroMotion?.refresh();
});

function showDialog(message){
  $('#retro-dialog').classList.remove('product-dialog');
  $('#dialog-content').textContent=message;
  $('#retro-dialog').showModal();
}
function openCard(index){
  const card=cards[index];
  const container=document.createElement('div');container.className='product-detail';
  const img=document.createElement('img');img.src=index===11?'assets/product/screen-12-content4.webp':`assets/product/screen-${String(index+1).padStart(2,'0')}.webp`;img.alt=card.title;
  const content=document.createElement('div');
  const title=document.createElement('h2');title.textContent=card.title;
  const caption=document.createElement('p');caption.textContent=card.caption;
  const detail=document.createElement('p');detail.textContent=card.detail;
  const note=document.createElement('p');note.className='source-note';note.textContent=card.image_type;
  const link=document.createElement('a');link.href=index===11?'downloads/LineSight-1.1.58-content8-production.apk':'demo/';link.className='retro-button';link.textContent=index===11?'↓ 下载 Android 1.1.58':'进入网页演示 →';
  if(index===11)link.setAttribute('download','');
  const banner=document.createElement('div');banner.className='detail-banner';banner.textContent='★ LineSight 产线视界 · 看见每一步 ★';
  content.append(title,caption,detail,note,link,banner);container.append(img,content);
  $('#dialog-content').replaceChildren(container);$('#retro-dialog').classList.add('product-dialog');$('#retro-dialog').showModal();
}
$('#close-dialog').addEventListener('click',()=>$('#retro-dialog').close());
$('#dialog-ok').addEventListener('click',()=>$('#retro-dialog').close());
$('#retro-dialog').addEventListener('click',event=>{
  if(event.target===$('#retro-dialog')){const r=event.target.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)event.target.close();}
});
let toastTimer;
function toast(message){$('#status-message').textContent=message;$('#status-message').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#status-message').classList.remove('visible'),2800);}
$('#save-site').addEventListener('click',()=>showDialog('收藏 LineSight 产线视界\n电脑：按 Ctrl+D（Mac：⌘D）收藏本站。\n手机：通过浏览器菜单添加书签。'));

let task=0;
const taskStates=['待打印','打印中','待质检','已关闭'];
const taskActions=['▶ 开始打印（点一下试试）','▶ 打印完成，送检','✓ 质检通过并关闭','↺ 再跑一遍这张任务'];
$('#advance-task').addEventListener('click',()=>{
  task=(task+1)%4;$('#task-step').textContent=String(task+1);$('#task-state').textContent=taskStates[task];$('#advance-task').textContent=taskActions[task];
  document.querySelectorAll('.task-steps span').forEach((span,i)=>span.classList.toggle('today',i===task));
  burst(290,930,14);toast('流程推进：'+taskStates[task]+'。每一次交接，状态都清楚。');
});
let checkCount=0;
const checks=['照片是否齐全？','外观是否已检查？','尺寸是否已核对？','处理备注是否已填写？'];
$('#next-check').addEventListener('click',()=>{
  checkCount=(checkCount+1)%5;$('#check-count').textContent=`${checkCount} / 4`;$('#check-progress').style.width=`${checkCount*25}%`;
  $('#check-hint').textContent=checkCount===4?'✓ 示例清单已核对，请由质检人员确认结论。':'下一项：'+checks[checkCount];
  $('#next-check').textContent=checkCount===4?'↺ 再检查一遍':'✓ 确认一项';
  burst(580,930,10,'#77d6e3');
});
$('#view-evidence').addEventListener('click',()=>openCard(3));

let remaining=60;let interval;let duration=60;
const tourHints=['第 1 站：工作台，把工位与异常看清。','第 2 站：生产任务，交接进度有记录。','第 3 站：图片证据，照片留痕一目了然。','第 4 站：团队协作，把异常交代清楚。'];
function renderTime(){$('#timer').textContent=`${String(Math.floor(remaining/60)).padStart(2,'0')}:${String(remaining%60).padStart(2,'0')}`;}
function stopTimer(){clearInterval(interval);interval=undefined;$('#start-timer').textContent='▶ 开始导览';}
function resetTimer(){stopTimer();remaining=duration=Number($('#training-preset').value);renderTime();$('#tour-hint').textContent='先看工作台，再看任务和图片证据。';}
$('#start-timer').addEventListener('click',()=>{
  if(interval){stopTimer();$('#start-timer').textContent='▶ 继续导览';return;}
  if(remaining<=0)remaining=duration=Number($('#training-preset').value);
  $('#start-timer').textContent='Ⅱ 暂停导览';$('#tour-hint').textContent=tourHints[Math.min(3,Math.floor((1-remaining/duration)*4))];
  interval=setInterval(()=>{
    remaining--;renderTime();$('#tour-hint').textContent=tourHints[Math.min(3,Math.floor((1-remaining/duration)*4))];
    if(remaining<=0){stopTimer();$('#tour-hint').textContent='导览完成！点击「网页演示」继续体验。';toast('LineSight 导览完成，现在进站开工吧。');burst(870,959,24);}
  },1000);
});
$('#reset-timer').addEventListener('click',resetTimer);$('#training-preset').addEventListener('change',resetTimer);

$('#guestbook').addEventListener('submit',event=>{
  event.preventDefault();const nickname=$('#nickname').value.trim()||'LineSight 访客';const message=$('#message').value.trim();
  if(!message){$('#message').focus();return toast('先写一句话，再贴到本页留言板。');}
  const block=document.createElement('div');block.className='guest-message';const name=document.createElement('strong');name.textContent=`${nickname}：`;
  block.append(name,document.createTextNode(message));$('#guestbook-messages').prepend(block);
  if($('#guestbook-messages').children.length>3)$('#guestbook-messages').lastElementChild.remove();
  $('#message').value='';toast('已贴到留言板，质检员在线看单。');
});
$('#search-form').addEventListener('submit',event=>{
  event.preventDefault();const query=$('#search').value.trim();if(!query)return toast('请输入产品功能，例如「任务」「图片」「备份」。');
  const index=cards.findIndex(card=>[card.title,card.category,card.caption,card.detail].join(' ').toLowerCase().includes(query.toLowerCase()));
  if(index<0)return showDialog(`本站搜索：${query}\n暂时没有找到相关内容。\n试试「任务」「图片」「团队」「备份」。`);
  const target=$('#gallery').children[index];target.scrollIntoView({behavior:motionQuery.matches?'instant':'smooth',block:'center'});target.style.outline='2px dotted #c08331';setTimeout(()=>target.style.outline='',3200);
});

// Period-style canvas glints, a light cursor trail, and celebratory click particles.
// No Flash, third-party library, network tracker, or continuous offscreen rendering.
const canvas = $('#sparkles');
const context = canvas.getContext('2d');
const particles = [];
let frame;
let previous = 0;
let lastPointer = 0;
const ambient = Array.from({ length: 39 }, (_, index) => ({
  x: index % 3 === 0 ? 10 + Math.random() * 72 : index % 3 === 1 ? 1090 + Math.random() * 70 : 852 + Math.random() * 205,
  y: index % 3 === 2 ? 60 + Math.random() * 535 : 25 + Math.random() * 1980,
  radius: 1.2 + Math.random() * 2.6,
  phase: Math.random() * Math.PI * 2,
  speed: .6 + Math.random() * .8,
}));
function drawStar(x, y, size, color, alpha) {
  context.globalAlpha = alpha;
  context.fillStyle = color;
  context.beginPath();
  context.moveTo(x, y - size);
  context.lineTo(x + size * .22, y - size * .22);
  context.lineTo(x + size, y);
  context.lineTo(x + size * .22, y + size * .22);
  context.lineTo(x, y + size);
  context.lineTo(x - size * .22, y + size * .22);
  context.lineTo(x - size, y);
  context.lineTo(x - size * .22, y - size * .22);
  context.closePath();
  context.fill();
}
function burst(x, y, count, color = '#f4cc64') {
  if (motionQuery.matches) return;
  for (let i = 0; i < count; i++) particles.push({ x, y, vx: (Math.random() - .5) * 3, vy: -Math.random() * 3 - .5, life: 1, size: 2 + Math.random() * 3, color });
}
portal.addEventListener('pointermove', event => {
  if (motionQuery.matches || event.pointerType === 'touch' || performance.now() - lastPointer < 65) return;
  lastPointer = performance.now();
  const r = portal.getBoundingClientRect();
  const scale = r.width / 1190;
  particles.push({ x: (event.clientX - r.left) / scale, y: (event.clientY - r.top) / scale, vx: (Math.random() - .5) * .9, vy: .45, life: .7, size: 2.6, color: '#d6af48' });
});
function animate(time) {
  frame = requestAnimationFrame(animate);
  if (time - previous < 32) return;
  const dt = Math.min((time - (previous || time)) / 33, 2);
  previous = time;
  context.clearRect(0, 0, 1190, 2048);
  const bounds = portal.getBoundingClientRect();
  const scale = bounds.width / 1190;
  const top = Math.max(0, -bounds.top / scale);
  const bottom = top + innerHeight / scale;
  ambient.forEach(star => {
    if (star.y < top - 10 || star.y > bottom + 10) return;
    const opacity = Math.max(0, Math.sin(time * .0013 * star.speed + star.phase));
    drawStar(star.x, star.y, star.radius * (opacity + .3), '#fff0a7', opacity * .82);
  });
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vy += .025 * dt;
    p.life -= .025 * dt;
    if (p.life <= 0) particles.splice(i, 1);
    else drawStar(p.x, p.y, p.size * p.life, p.color, p.life);
  }
  context.globalAlpha = 1;
}
function updateAnimation() {
  cancelAnimationFrame(frame);
  previous = 0;
  if (motionQuery.matches || document.hidden) context.clearRect(0, 0, 1190, 2048);
  else frame = requestAnimationFrame(animate);
}
document.addEventListener('visibilitychange', updateAnimation);
motionQuery.addEventListener('change', updateAnimation);
updateAnimation();
