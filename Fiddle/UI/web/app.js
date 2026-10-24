  // ====================================================================
  //  Fiddle live UI. The look is the mockup, unchanged. Behavior now talks
  //  to the native engine over the typed bridge in Fiddle/Bridge/Protocol.swift:
  //    out: window.webkit.messageHandlers.fiddle.postMessage({type,...})
  //    in:  window.fiddleEvent(e)  (called from Swift via evaluateJavaScript)
  // ====================================================================

  // ---------- view state (mirrors the form fields) ----------
  const state = {
    surface:'window',
    cat:'home', running:false, simpleTab:'click',
    prefs:{ launchAtLogin:false, menuBarOnly:false, soundOnClick:false, skin:'red', interfaceMode:'advanced' },
    clicker:{ hrs:0, min:0, sec:0, ms:100, button:'Left', type:'Single', repeat:'until', times:50, pos:'current', x:640, y:480, rate:5, rateUnit:'minute' },
    jiggler:{ secs:30, dist:40, mode:'Zen', wake:true, idleOnly:true },
    wakelock:{ keepDisplay:true, keepSystem:false },
    antiafk:{ secs:60, dist:30, keepAwake:true },
    hotkeys:{ startStop:'F6', toggleJiggler:'F7', pickPosition:'ctrl+opt+KeyP', panic:'cmd+Escape' },
    recorder:{ repeat:'until', times:5 },
    recording:[], recordingActive:false, inputMonitoring:true,
    macros:[], selectedMacro:null, macroRepeat:{ repeat:'until', times:1 }, pendingPick:null,
    device:'mouse',
    keyboard:{ hrs:0, min:0, sec:1, ms:0, combo:'Space', repeat:'until', times:50 },
    profiles:[], activity:[],
  };

  const titles = {
    home:['Favorites','Pick a task to get started'],
    clicker:['Auto Clicker','Configure automated clicking'],
    jiggler:['Mouse Jiggler','Keep your Mac awake and active'],
    recorder:['Click Recorder','Capture and replay click sequences'],
    hotkeys:['Hotkeys','Global shortcuts to start &amp; stop'],
    more:['More','Preferences &amp; about'],
    wakelock:['Wake Lock','Keep your Mac from sleeping'],
    antiafk:['Anti-AFK','Stay active so you are not marked away'],
    sequencer:['Click Sequencer','Build a macro step by step'],
    macro:['Macro Player','Play a saved macro'],
    profiles:['Profiles','Saved automation setups'],
    activity:['Activity Log','What fiddle has been doing'],
  };

  const content = document.getElementById('content');

  // ---------- bridge ----------
  function send(msg){
    try { window.webkit.messageHandlers.fiddle.postMessage(msg); }
    catch (e) { console.log('[fiddle] no native bridge:', msg); }
  }

  // Flatten the clicker form into the wire ClickerConfig shape.
  function clickerConfig(){
    const c = state.clicker;
    // Simple mode and the menu-bar popover use a continuous rate (clicks per
    // second/minute); Advanced uses the explicit hrs/min/sec/ms interval.
    const rateMode = state.surface==='menubar' || state.prefs.interfaceMode==='simple';
    const rate = Math.max(1, +c.rate||1);
    // Swift decodes every numeric here as Int; a fractional value fails the
    // decode and the whole command is dropped, so round at the boundary.
    const intervalMs = rateMode
      ? Math.max(10, Math.round((c.rateUnit==='minute' ? 60000 : 1000) / rate))
      : Math.round((((+c.hrs||0)*60 + (+c.min||0))*60 + (+c.sec||0))*1000 + (+c.ms||0));
    return {
      // All-blank interval fields mean "unset", not "as fast as possible";
      // fall back to the 100ms default instead of a 1ms machine gun. Floor
      // any explicit value at 10ms so a typo can't arm a machine-gun interval.
      intervalMs: intervalMs > 0 ? Math.max(10, intervalMs) : 100,
      button: c.button.toLowerCase(),
      clickType: c.type.toLowerCase(),
      repeat: rateMode ? 'until' : c.repeat,
      times: Math.round(Math.max(1, +c.times||1)),
      position: c.pos === 'pick' ? 'fixed' : 'current',
      x: Math.round(+c.x||0), y: Math.round(+c.y||0),
      rate: Math.round(rate),
      rateUnit: c.rateUnit==='second' ? 'second' : 'minute',
    };
  }
  function jigglerConfig(){
    const j = state.jiggler;
    return {
      intervalSec: Math.round(Math.max(1, +j.secs||1)),
      distancePx: Math.round(Math.max(1, +j.dist||1)),
      mode: j.mode.toLowerCase(),
      keepAwake: !!j.wake,
      idleOnly: !!j.idleOnly,
    };
  }
  function currentMode(){
    if(state.surface==='menubar') return state.simpleTab==='jiggle' ? 'jiggler' : 'clicker';
    if(state.prefs.interfaceMode==='simple') return state.simpleTab==='jiggle' ? 'jiggler' : 'clicker';
    if(state.cat==='clicker' && state.device==='keyboard') return 'keyboard';
    return ({jiggler:'jiggler', wakelock:'wakeLock', antiafk:'antiAFK', recorder:'recorder', sequencer:'macro', macro:'macro'})[state.cat] || 'clicker';
  }
  function currentConfig(m){
    if(m==='jiggler') return jigglerConfig();
    if(m==='wakeLock') return { keepDisplayAwake: !!state.wakelock.keepDisplay, keepSystemAwake: !!state.wakelock.keepSystem };
    if(m==='antiAFK')  return { intervalSec: Math.round(Math.max(1, +state.antiafk.secs||1)), distancePx: Math.round(Math.max(1, +state.antiafk.dist||1)), keepAwake: !!state.antiafk.keepAwake };
    if(m==='recorder')  return { repeat: state.recorder.repeat, times: Math.round(Math.max(1, +state.recorder.times||1)) };
    if(m==='macro'){
      const id = state.selectedMacro || (state.macros[0] && state.macros[0].id) || '';
      return { macroId:id, repeat: state.macroRepeat.repeat, times: Math.round(Math.max(1, +state.macroRepeat.times||1)) };
    }
    if(m==='keyboard') return keyboardConfig();
    return clickerConfig();
  }

  // ---------- views ----------
  function viewHome(){
    const tasks = [
      ['clicker', taskMouse(), 'Auto Clicker', 'Click on a fixed interval, set the button, repeat count and target position.'],
      ['jiggler', taskJiggle(), 'Mouse Jiggler', 'Nudge the cursor every few seconds to stop your Mac from sleeping.'],
      ['recorder', taskRec(), 'Click Recorder', 'Record a sequence of clicks and play it back on demand.'],
      ['hotkeys', taskKey(), 'Hotkeys', 'Bind a global key to start and stop without touching the window.'],
    ];
    content.innerHTML = tasks.map(t=>`
      <div class="task" data-go="${t[0]}">
        <div class="task-ico">${t[1]}</div>
        <div><div class="task-t">${t[2]}</div><div class="task-s">${t[3]}</div></div>
      </div>`).join('');
    content.querySelectorAll('[data-go]').forEach(el=>el.onclick=()=>selectCat(el.dataset.go, true));
  }

  // Persist the current mode's config so the non-flame start paths (global
  // hotkey, menu bar) use what the user set. Debounced 250ms per pause in
  // editing, not per keystroke: every send re-encodes the whole settings blob
  // on the Swift side and re-syncs the other surface. Consequence: a hotkey
  // start within 250ms of the last keystroke runs the previous value; the
  // flame is unaffected (it sends its config inline). Switching modes flushes
  // the pending edit immediately so it is never dropped.

  // The popover web view lives (hidden) for the app's lifetime and receives
  // every broadcast. Rendering it while hidden wastes a layout+paint per edit
  // and can blow away a live input; render once on reveal instead.
  let menubarDirty = false;
  function renderMenubar(){
    if(document.hidden){ menubarDirty = true; return; }
    viewMenubar(); applyBanner();
  }
  document.addEventListener('visibilitychange', ()=>{
    if(!document.hidden && menubarDirty && state.surface==='menubar'){
      menubarDirty = false;
      viewMenubar(); applyBanner();
    }
  });

  let persistTimer=null, persistMode=null;
  function flushPersist(){
    if(!persistTimer) return;
    clearTimeout(persistTimer);
    persistTimer=null;
    send({type:'updateConfig', mode:persistMode, config:currentConfig(persistMode)});
  }
  function persist(){
    const m=currentMode();
    if(persistTimer && persistMode!==m) flushPersist();
    persistMode=m;
    clearTimeout(persistTimer);
    persistTimer=setTimeout(()=>{ persistTimer=null; send({type:'updateConfig', mode:m, config:currentConfig(m)}); }, 250);
  }
  window.addEventListener('blur', flushPersist);
  window.addEventListener('blur', flushSaveMacros);

  function viewClicker(){
    if(state.device==='keyboard') return viewKeyboard();
    const c=state.clicker;
    content.innerHTML=`
      <div class="group"><h4>Click Interval</h4>
        <div class="row">
          <span class="lab">Every</span>
          <input class="field" id="iv-h" value="${c.hrs}" aria-label="Hours"><span class="hint">hrs</span>
          <input class="field" id="iv-m" value="${c.min}" aria-label="Minutes"><span class="hint">min</span>
          <input class="field" id="iv-s" value="${c.sec}" aria-label="Seconds"><span class="hint">sec</span>
          <input class="field" id="iv-ms" value="${c.ms}" aria-label="Milliseconds"><span class="hint">ms</span>
        </div>
      </div>
      <div class="group"><h4>Click Options</h4>
        <div class="row">
          <span class="lab">Mouse button</span>
          <select class="field" id="btn" aria-label="Mouse button">${opt(['Left','Right','Middle'],c.button)}</select>
          <span class="lab" style="min-width:auto">Type</span>
          <div class="seg" id="ctype">
            <button data-v="Single" class="${c.type==='Single'?'on':''}">Single</button>
            <button data-v="Double" class="${c.type==='Double'?'on':''}">Double</button>
          </div>
        </div>
      </div>
      <div class="group"><h4>Click Repeat</h4>
        <div class="row">
          <label class="radio"><input type="radio" name="rep" value="times" ${c.repeat==='times'?'checked':''}> Repeat</label>
          <input class="field" id="times" value="${c.times}" aria-label="Number of times to repeat"><span class="hint">times</span>
          <label class="radio"><input type="radio" name="rep" value="until" ${c.repeat==='until'?'checked':''}> Repeat until stopped</label>
        </div>
      </div>
      <div class="group"><h4>Cursor Position</h4>
        <div class="row">
          <label class="radio"><input type="radio" name="pos" value="current" ${c.pos==='current'?'checked':''}> Current location</label>
          <label class="radio"><input type="radio" name="pos" value="pick" ${c.pos==='pick'?'checked':''}> Pick&nbsp;</label>
          X <input class="field" id="px" value="${c.x}" aria-label="X position"> Y <input class="field" id="py" value="${c.y}" aria-label="Y position">
        </div>
      </div>`;
    bind('iv-h', v=>{c.hrs=+v||0; persist();});
    bind('iv-m', v=>{c.min=+v||0; persist();});
    bind('iv-s', v=>{c.sec=+v||0; persist();});
    bind('iv-ms', v=>{c.ms=+v||0; persist();});
    document.getElementById('btn').onchange=e=>{c.button=e.target.value; persist();};
    seg('ctype', v=>{c.type=v; persist();});
    content.querySelectorAll('[name=rep]').forEach(r=>r.onchange=e=>{c.repeat=e.target.value; persist();});
    content.querySelectorAll('[name=pos]').forEach(r=>r.onchange=e=>{
      c.pos=e.target.value;
      if(e.target.value==='pick') send({type:'pickPosition'}); // engine enters position-pick mode
      persist();
    });
    bind('times', v=>{c.times=+v||0; persist();});
    bind('px', v=>{c.x=+v||0; persist();});
    bind('py', v=>{c.y=+v||0; persist();});
  }

  function keyboardConfig(){
    const k=state.keyboard;
    const intervalMs=Math.round((((+k.hrs||0)*60+(+k.min||0))*60+(+k.sec||0))*1000+(+k.ms||0));
    // Same floor as clickerConfig: an explicit sub-10ms interval can't arm a
    // machine-gun keystroke rate; all-blank stays 1000ms.
    return { combo:k.combo||'Space', intervalMs: intervalMs>0?Math.max(10,intervalMs):1000, repeat:k.repeat, times:Math.round(Math.max(1,+k.times||1)) };
  }
  function beginKeyCapture(btn){
    // Already capturing on this keycap: a second click must not re-snapshot
    // the "press a key" prompt as the restore label.
    if(btn.classList.contains('capturing')) return;
    if(keyCaptureHandler){ document.removeEventListener('keydown', keyCaptureHandler, true); keyCaptureHandler=null; }
    const prev=btn.innerHTML;
    btn.textContent='press a key…'; btn.classList.add('capturing');
    function onKey(e){
      if(!document.getElementById('kKey')){ document.removeEventListener('keydown', onKey, true); keyCaptureHandler=null; return; }
      e.preventDefault(); e.stopPropagation();
      const code=e.code;
      if(/^(Control|Shift|Alt|Meta)(Left|Right)$/.test(code) || code==='CapsLock') return;
      const mods=[];
      if(e.ctrlKey) mods.push('ctrl');
      if(e.altKey)  mods.push('opt');
      if(e.shiftKey)mods.push('shift');
      if(e.metaKey) mods.push('cmd');
      if(code==='Escape' && mods.length===0){ btn.innerHTML=prev; btn.classList.remove('capturing'); document.removeEventListener('keydown',onKey,true); keyCaptureHandler=null; return; }
      state.keyboard.combo=[...mods, code].join('+');
      document.removeEventListener('keydown',onKey,true); keyCaptureHandler=null;
      persist();
      viewKeyboard(); applyBanner();
    }
    keyCaptureHandler=onKey;
    document.addEventListener('keydown', onKey, true);
  }
  function viewKeyboard(){
    const k=state.keyboard;
    content.innerHTML=
      `<div class="group"><h4>Press Interval</h4>
        <div class="row"><span class="lab">Every</span>
          <input class="field" id="kv-h" value="${k.hrs}" aria-label="Hours"><span class="hint">hrs</span>
          <input class="field" id="kv-m" value="${k.min}" aria-label="Minutes"><span class="hint">min</span>
          <input class="field" id="kv-s" value="${k.sec}" aria-label="Seconds"><span class="hint">sec</span>
          <input class="field" id="kv-ms" value="${k.ms}" aria-label="Milliseconds"><span class="hint">ms</span></div>
      </div>
      <div class="group"><h4>Key</h4>
        <div class="row"><span class="lab">Key to press</span>
          <button class="keycap" id="kKey" aria-label="Key to press, click then press a key">${comboGlyphs(k.combo)}</button>
          <span class="hint">click, then press a key (modifiers ok)</span></div>
      </div>
      <div class="group"><h4>Repeat</h4>
        <div class="row">
          <label class="radio"><input type="radio" name="krep" value="times" ${k.repeat==='times'?'checked':''}> Repeat</label>
          <input class="field" id="ktimes" value="${k.times}" aria-label="Number of times to repeat"><span class="hint">times</span>
          <label class="radio"><input type="radio" name="krep" value="until" ${k.repeat==='until'?'checked':''}> Repeat until stopped</label></div>
      </div>`;
    bind('kv-h', v=>{k.hrs=+v||0; persist();}); bind('kv-m', v=>{k.min=+v||0; persist();}); bind('kv-s', v=>{k.sec=+v||0; persist();}); bind('kv-ms', v=>{k.ms=+v||0; persist();});
    document.getElementById('kKey').onclick=()=>beginKeyCapture(document.getElementById('kKey'));
    content.querySelectorAll('input[name=krep]').forEach(r=>r.onchange=()=>{ k.repeat=document.querySelector('input[name=krep]:checked').value; persist(); });
    bind('ktimes', v=>{k.times=+v||1; persist();});
  }

  function viewJiggler(){
    const j=state.jiggler;
    content.innerHTML=`
      <div class="group"><h4>Jiggle Interval</h4>
        <div class="row"><span class="lab">Every</span>
          <input class="field" id="js" value="${j.secs}" aria-label="Jiggle interval in seconds"><span class="hint">seconds</span></div>
      </div>
      <div class="group"><h4>Movement</h4>
        <div class="row"><span class="lab">Distance</span>
          <input type="range" min="1" max="120" id="jd" value="${j.dist}" style="width:160px;accent-color:#e2381f" aria-label="Jiggle distance in pixels">
          <span class="hint"><span id="jdval">${j.dist}</span> px</span></div>
        <div class="row"><span class="lab">Mode</span>
          <div class="seg" id="jmode">
            <button data-v="Zen" class="${j.mode==='Zen'?'on':''}">Zen (invisible)</button>
            <button data-v="Visible" class="${j.mode==='Visible'?'on':''}">Visible</button>
          </div></div>
      </div>
      <div class="group"><h4>Behavior</h4>
        <div class="row"><span class="lab">Keep display awake</span>
          <div class="toggle ${j.wake?'on':''}" id="tg-wake"><div class="knob"></div></div></div>
        <div class="row"><span class="lab">Only when idle</span>
          <div class="toggle ${j.idleOnly?'on':''}" id="tg-idle"><div class="knob"></div></div>
          <span class="hint">pause jiggling while you are actively using the Mac</span></div>
      </div>`;
    const r=document.getElementById('jd');
    r.oninput=e=>{j.dist=+e.target.value;document.getElementById('jdval').textContent=j.dist; persist();};
    bind('js', v=>{j.secs=+v||0; persist();});
    seg('jmode', v=>{j.mode=v; persist();});
    toggle('tg-wake', v=>{j.wake=v; persist();});
    toggle('tg-idle', v=>{j.idleOnly=v; persist();});
  }

  function viewWakeLock(){
    const w=state.wakelock;
    content.innerHTML=`
      <div class="group"><h4>Wake Lock</h4>
        <div class="row"><span class="lab">Keep display awake</span>
          <div class="toggle ${w.keepDisplay?'on':''}" id="wl-disp"><div class="knob"></div></div></div>
        <div class="row"><span class="lab">Also prevent system sleep</span>
          <div class="toggle ${w.keepSystem?'on':''}" id="wl-sys"><div class="knob"></div></div>
          <span class="hint">holds the Mac fully awake, not just the display</span></div>
      </div>`;
    toggle('wl-disp', v=>{w.keepDisplay=v; persist();});
    toggle('wl-sys', v=>{w.keepSystem=v; persist();});
  }
  function viewAntiAFK(){
    const a=state.antiafk;
    content.innerHTML=`
      <div class="group"><h4>Activity</h4>
        <div class="row"><span class="lab">Every</span>
          <input class="field" id="afk-secs" value="${a.secs}" aria-label="Interval in seconds"><span class="hint">seconds</span></div>
        <div class="row"><span class="lab">Nudge distance</span>
          <input type="range" min="1" max="120" id="afk-dist" value="${a.dist}" style="width:160px;accent-color:#e2381f" aria-label="Nudge distance in pixels">
          <span class="hint"><span id="afk-distval">${a.dist}</span> px</span></div>
      </div>
      <div class="group"><h4>Behavior</h4>
        <div class="row"><span class="lab">Keep display awake too</span>
          <div class="toggle ${a.keepAwake?'on':''}" id="afk-wake"><div class="knob"></div></div></div>
      </div>`;
    bind('afk-secs', v=>{a.secs=+v||0; persist();});
    const r=document.getElementById('afk-dist');
    r.oninput=e=>{a.dist=+e.target.value;document.getElementById('afk-distval').textContent=a.dist; persist();};
    toggle('afk-wake', v=>{a.keepAwake=v; persist();});
  }

  function viewRecorder(){
    const r=state.recorder;
    const recording=state.recordingActive;
    const steps=state.recording||[];
    const RECORDER_RENDER_CAP = 200;
    const shown = steps.slice(0, RECORDER_RENDER_CAP);
    const list = steps.length
      ? shown.map((s,i)=>`<div class="step">${i+1} · ${s.label} @ (${s.x}, ${s.y}) <span>+${(s.delayMs/1000).toFixed(2)}s</span></div>`).join('')
        + (steps.length > RECORDER_RENDER_CAP
            ? `<div class="step" style="opacity:.7">Showing the first ${RECORDER_RENDER_CAP} of ${steps.length} steps. All of them play back and import.</div>`
            : '')
      : `<div class="step" style="opacity:.7">No steps yet. Click Record, then click around in another app.</div>`;
    const permNote = state.inputMonitoring ? '' :
      `<div class="row"><span class="hint" style="color:#ffd9a0">Input Monitoring permission required to record. </span>
        <button class="btn-reset" id="recPerm">Open System Settings</button></div>`;
    content.innerHTML=
      `<div class="group"><h4>Capture</h4>
        <div class="row">
          <div class="seg"><button id="recBtn" class="${recording?'on':''}" aria-pressed="${recording?'true':'false'}">${recording?'■ Stop':'● Record'}</button><button id="recClear">✕ Clear</button></div>
          <span class="hint">${recording?'recording your clicks…':'records clicks in any app'}</span>
        </div>
        ${permNote}
      </div>
      <div class="group"><h4>Sequence</h4>
        <div class="reclist">${list}</div>
      </div>
      <div class="group"><h4>Playback</h4>
        <div class="row"><span class="lab">Repeat</span>
          <div class="seg" id="recRepeat"><button data-v="until" class="${r.repeat==='until'?'on':''}">Until stopped</button><button data-v="times" class="${r.repeat==='times'?'on':''}">Times</button></div></div>
        <div class="row"><span class="lab">Count</span>
          <input class="field" id="recTimes" value="${r.times}" aria-label="Number of times to repeat"><span class="hint">times (when Times is selected)</span></div>
      </div>`;
    const recBtn=document.getElementById('recBtn');
    if(recBtn) recBtn.onclick=()=>send({type: state.recordingActive ? 'recordStop' : 'recordStart'});
    const recClear=document.getElementById('recClear');
    if(recClear) recClear.onclick=()=>{
      if(!(state.recording||[]).length) return;
      const kept=state.recording;
      state.recording=[]; if(state.cat==='recorder'){ viewRecorder(); applyBanner(); }
      showUndo('Recording cleared.',
        ()=>{ state.recording=kept; if(state.cat==='recorder'){ viewRecorder(); applyBanner(); } },
        ()=>send({type:'clearRecording'}));
    };
    const recPerm=document.getElementById('recPerm');
    if(recPerm) recPerm.onclick=()=>send({type:'openSettings', pane:'inputMonitoring'});
    seg('recRepeat', v=>{r.repeat=v; persist();});
    bind('recTimes', v=>{r.times=+v||1; persist();});
  }

  // ---------- macros ----------
  function macroId(){ return 'm' + (state.macros.reduce((n,m)=>Math.max(n, +(m.id||'m0').slice(1)||0),0) + 1); }
  function selectedMacro(){ return state.macros.find(m=>m.id===state.selectedMacro) || state.macros[0] || null; }
  // Debounce macro saves the same way config edits are debounced above: every
  // send serializes the whole macro library across the bridge and re-encodes
  // the entire settings blob. Rendering stays immediate; only the bridge send
  // waits out a 250ms pause, and is flushed on blur so it is never dropped.
  let saveMacrosTimer=null;
  function flushSaveMacros(){
    if(!saveMacrosTimer) return;
    clearTimeout(saveMacrosTimer);
    saveMacrosTimer=null;
    send({type:'saveMacros', macros: state.macros});
  }
  function saveMacros(){
    clearTimeout(saveMacrosTimer);
    saveMacrosTimer=setTimeout(()=>{ saveMacrosTimer=null; send({type:'saveMacros', macros: state.macros}); }, 250);
  }
  function stepStep(kind){
    return { kind, button:'left', clickType:'single', x:0, y:0, ms:(kind==='wait'?200:0) };
  }
  function stepSummary(s){
    if(s.kind==='wait') return `Wait ${s.ms} ms`;
    if(s.kind==='move') return `Move to (${s.x}, ${s.y})`;
    const t = s.clickType==='double'?'double ':'';
    return `${s.button} ${t}click @ (${s.x}, ${s.y})`;
  }

  function viewSequencer(){
    if(!selectedMacro() && state.macros.length) state.selectedMacro = state.macros[0].id;
    const m = selectedMacro();
    const opts = state.macros.map(x=>`<option value="${esc(x.id)}" ${m&&x.id===m.id?'selected':''}>${esc(x.name)}</option>`).join('');
    const steps = m ? m.steps.map((s,i)=>
      `<div class="step">${i+1} · ${stepSummary(s)}
        <span><button class="btn-reset" data-up="${i}">↑</button>
              <button class="btn-reset" data-down="${i}">↓</button>
              <button class="btn-reset" data-del="${i}">✕</button></span></div>`).join('') : '';
    content.innerHTML=
      `<div class="group"><h4>Macro</h4>
        <div class="row"><span class="lab">Library</span>
          <select class="field" id="macroSel" aria-label="Macro library">${opts || '<option>(none)</option>'}</select>
          <button class="btn-reset" id="macroNew">New</button>
          <button class="btn-reset" id="macroRen">Rename</button>
          <button class="btn-reset" id="macroDup">Duplicate</button>
          <button class="btn-reset" id="macroDel">Delete</button></div>
      </div>
      <div class="group"><h4>Steps</h4>
        <div class="reclist">${steps || '<div class="step" style="opacity:.7">No steps yet. Add one below.</div>'}</div>
        <div class="row"><button class="btn-reset" id="impRec">Import last recording</button></div>
      </div>
      <div class="group"><h4>Add step</h4>
        <div class="row"><div class="seg" id="addKind"><button data-v="click" class="on">Click</button><button data-v="wait">Wait</button><button data-v="move">Move</button></div></div>
        <div class="row" id="addClick"><span class="lab">Button</span>
          <div class="seg" id="addBtn"><button data-v="left" class="on">Left</button><button data-v="right">Right</button><button data-v="middle">Middle</button></div>
          <div class="seg" id="addType"><button data-v="single" class="on">Single</button><button data-v="double">Double</button></div></div>
        <div class="row" id="addPos"><span class="lab">Position</span>
          <input class="field" id="addX" placeholder="x" value="0" style="width:64px" aria-label="X position">
          <input class="field" id="addY" placeholder="y" value="0" style="width:64px" aria-label="Y position">
          <button class="btn-reset" id="addPick">Pick</button></div>
        <div class="row" id="addWait" style="display:none"><span class="lab">Wait</span>
          <input class="field" id="addMs" value="200" style="width:80px" aria-label="Wait time in milliseconds"><span class="hint">ms</span></div>
        <div class="row"><button class="btn-reset" id="addStep">+ Add step</button></div>
      </div>`;
    // library controls
    const sel=document.getElementById('macroSel'); if(sel) sel.onchange=()=>{ state.selectedMacro=sel.value; viewSequencer(); applyBanner(); };
    wireMacroLibraryButtons();
    // step list controls
    content.querySelectorAll('[data-up]').forEach(b=>b.onclick=()=>reorderStep(+b.dataset.up,-1));
    content.querySelectorAll('[data-down]').forEach(b=>b.onclick=()=>reorderStep(+b.dataset.down,1));
    content.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>deleteStep(+b.dataset.del));
    document.getElementById('impRec').onclick=importRecording;
    // add-step form
    let addState={ kind:'click', button:'left', clickType:'single' };
    seg('addKind', v=>{ addState.kind=v;
      document.getElementById('addClick').style.display = v==='click' ? '' : 'none';
      document.getElementById('addPos').style.display   = v==='wait' ? 'none' : '';
      document.getElementById('addWait').style.display  = v==='wait' ? '' : 'none';
    });
    seg('addBtn', v=>addState.button=v);
    seg('addType', v=>addState.clickType=v);
    document.getElementById('addPick').onclick=()=>{ state.pendingPick={view:'sequencer'}; send({type:'pickPosition', purpose:'step'}); };
    document.getElementById('addStep').onclick=()=>{
      const mm=selectedMacro(); if(!mm) return;
      const s=stepStep(addState.kind);
      if(addState.kind==='click'){ s.button=addState.button; s.clickType=addState.clickType; s.x=Math.round(+document.getElementById('addX').value||0); s.y=Math.round(+document.getElementById('addY').value||0); }
      else if(addState.kind==='move'){ s.x=Math.round(+document.getElementById('addX').value||0); s.y=Math.round(+document.getElementById('addY').value||0); }
      else { s.ms=Math.round(+document.getElementById('addMs').value||0); }
      mm.steps.push(s); saveMacros(); viewSequencer(); applyBanner();
    };
  }

  function wireMacroLibraryButtons(){
    const nw=document.getElementById('macroNew');
    if(nw) nw.onclick=()=>{ const id=macroId(); state.macros.push({id, name:'Macro '+id.slice(1), steps:[]}); state.selectedMacro=id; saveMacros(); rerenderMacroViews(); };
    const ren=document.getElementById('macroRen');
    if(ren) ren.onclick=()=>{ const m=selectedMacro(); if(!m) return; const name=prompt('Macro name', m.name); if(name){ m.name=name; saveMacros(); rerenderMacroViews(); } };
    const dup=document.getElementById('macroDup');
    if(dup) dup.onclick=()=>{ const m=selectedMacro(); if(!m) return; const id=macroId(); state.macros.push({id, name:m.name+' copy', steps:JSON.parse(JSON.stringify(m.steps))}); state.selectedMacro=id; saveMacros(); rerenderMacroViews(); };
    const del=document.getElementById('macroDel');
    if(del) del.onclick=()=>{ const m=selectedMacro(); if(!m) return;
      const idx=state.macros.indexOf(m);
      state.macros=state.macros.filter(x=>x.id!==m.id);
      state.selectedMacro=state.macros[0]?state.macros[0].id:null;
      saveMacros(); rerenderMacroViews();
      showUndo(`Macro "${m.name}" deleted.`,
        ()=>{ state.macros.splice(Math.min(idx,state.macros.length),0,m); state.selectedMacro=m.id; saveMacros(); rerenderMacroViews(); });
    };
  }
  function rerenderMacroViews(){ if(state.cat==='sequencer'){ viewSequencer(); applyBanner(); } if(state.cat==='macro'){ viewMacroPlayer(); applyBanner(); } }
  function reorderStep(i,dir){ const m=selectedMacro(); if(!m) return; const j=i+dir; if(j<0||j>=m.steps.length) return; const t=m.steps[i]; m.steps[i]=m.steps[j]; m.steps[j]=t; saveMacros(); viewSequencer(); applyBanner(); }
  function deleteStep(i){ const m=selectedMacro(); if(!m) return; m.steps.splice(i,1); saveMacros(); viewSequencer(); applyBanner(); }
  function importRecording(){
    const m=selectedMacro(); if(!m) return;
    // The native side is the real enforcement (FiddleController.capped truncates
    // the saved library to 10,000 steps total), but importing appends a wait
    // plus an action per recorded step, so a long recording can build a huge
    // array in memory before that cap ever runs. Stop early here too.
    const budget = 10000 - m.steps.length;
    if(budget<=0) return;
    let added=0;
    const recording = state.recording||[];
    for(let i=0;i<recording.length;i++){
      if(added>=budget) break;
      const s=recording[i];
      if(s.delayMs>0){ m.steps.push({kind:'wait', button:'left', clickType:'single', x:0, y:0, ms:s.delayMs}); added++; }
      const button=['left','right','middle'].includes(s.button)?s.button:'left';
      const clickType=s.clickType==='double'?'double':'single';
      // A press whose release landed elsewhere still becomes a click at the
      // press point. Dropping it lost the click entirely. The matching
      // release is skipped so one physical click yields one step.
      if(s.kind==='click' || s.kind==='press'){
        m.steps.push({kind:'click', button:button, clickType:clickType, x:s.x, y:s.y, ms:0}); added++;
      } else if(s.kind==='move'){
        m.steps.push({kind:'move', button:'left', clickType:'single', x:s.x, y:s.y, ms:0}); added++;
      }
    }
    saveMacros(); viewSequencer(); applyBanner();
  }

  function viewMacroPlayer(){
    if(!selectedMacro() && state.macros.length) state.selectedMacro = state.macros[0].id;
    const m = selectedMacro();
    const opts = state.macros.map(x=>`<option value="${esc(x.id)}" ${m&&x.id===m.id?'selected':''}>${esc(x.name)}</option>`).join('');
    const r = state.macroRepeat;
    const steps = m ? m.steps.map((s,i)=>`<div class="step">${i+1} · ${stepSummary(s)}</div>`).join('') : '';
    content.innerHTML=
      `<div class="group"><h4>Macro</h4>
        <div class="row"><span class="lab">Play</span>
          <select class="field" id="mpSel" aria-label="Macro to play">${opts || '<option>(none)</option>'}</select>
          <button class="btn-reset" id="mpDup">Duplicate</button>
          <button class="btn-reset" id="mpDel">Delete</button></div>
        <div class="row"><span class="hint">${m ? '' : 'No macros yet. Build one in Click Sequencer.'}</span></div>
      </div>
      <div class="group"><h4>Steps</h4>
        <div class="reclist">${steps || '<div class="step" style="opacity:.7">No steps.</div>'}</div>
      </div>
      <div class="group"><h4>Playback</h4>
        <div class="row"><span class="lab">Repeat</span>
          <div class="seg" id="mpRepeat"><button data-v="until" class="${r.repeat==='until'?'on':''}">Until stopped</button><button data-v="times" class="${r.repeat==='times'?'on':''}">Times</button></div></div>
        <div class="row"><span class="lab">Count</span>
          <input class="field" id="mpTimes" value="${r.times}" aria-label="Number of times to repeat"><span class="hint">times (when Times is selected)</span></div>
      </div>`;
    const sel=document.getElementById('mpSel'); if(sel) sel.onchange=()=>{ state.selectedMacro=sel.value; viewMacroPlayer(); applyBanner(); };
    const dup=document.getElementById('mpDup'); if(dup) dup.onclick=()=>{ const mm=selectedMacro(); if(!mm) return; const id=macroId(); state.macros.push({id, name:mm.name+' copy', steps:JSON.parse(JSON.stringify(mm.steps))}); state.selectedMacro=id; saveMacros(); rerenderMacroViews(); };
    const del=document.getElementById('mpDel'); if(del) del.onclick=()=>{ const mm=selectedMacro(); if(!mm) return;
      const idx=state.macros.indexOf(mm);
      state.macros=state.macros.filter(x=>x.id!==mm.id);
      state.selectedMacro=state.macros[0]?state.macros[0].id:null;
      saveMacros(); rerenderMacroViews();
      showUndo(`Macro "${mm.name}" deleted.`,
        ()=>{ state.macros.splice(Math.min(idx,state.macros.length),0,mm); state.selectedMacro=mm.id; saveMacros(); rerenderMacroViews(); });
    };
    seg('mpRepeat', v=>r.repeat=v);
    bind('mpTimes', v=>r.times=+v||1);
  }

  function profileId(){ return 'p' + (state.profiles.reduce((n,p)=>Math.max(n, +(p.id||'p0').slice(1)||0),0) + 1); }
  function captureProfile(name){
    return { id:profileId(), name,
      // Reuse the wire builders so every numeric is rounded the same way a
      // start/updateConfig payload is; hand-built shapes here leaked
      // fractional values that failed the Swift Int decode.
      clicker:clickerConfig(), jiggler:jigglerConfig(),
      wakeLock:currentConfig('wakeLock'),
      antiAFK:currentConfig('antiAFK'),
      keyboard:keyboardConfig(), device:state.device };
  }
  function viewProfiles(){
    const rows = state.profiles.map(p=>
      `<div class="step">${esc(p.name)} <span><button class="btn-reset" data-apply="${esc(p.id)}">Apply</button> <button class="btn-reset" data-delp="${esc(p.id)}">✕</button></span></div>`).join('');
    content.innerHTML=
      `<div class="group"><h4>Profiles</h4>
        <div class="reclist">${rows || '<div class="step" style="opacity:.7">No profiles yet. Save your current setup below.</div>'}</div>
      </div>
      <div class="group"><h4>Save</h4>
        <div class="row"><button class="btn-reset" id="profSave">Save current as profile</button>
          <span class="hint">captures clicker, jiggler, wake lock, anti-AFK, keyboard + device</span></div>
      </div>`;
    content.querySelectorAll('[data-apply]').forEach(b=>b.onclick=()=>send({type:'applyProfile', id:b.dataset.apply}));
    content.querySelectorAll('[data-delp]').forEach(b=>b.onclick=()=>{
      const idx=state.profiles.findIndex(p=>p.id===b.dataset.delp);
      if(idx<0) return;
      const p=state.profiles[idx];
      state.profiles=state.profiles.filter(x=>x.id!==p.id);
      send({type:'saveProfiles', profiles:state.profiles});
      viewProfiles(); applyBanner();
      showUndo(`Profile "${p.name}" deleted.`,
        ()=>{ state.profiles.splice(Math.min(idx,state.profiles.length),0,p); send({type:'saveProfiles', profiles:state.profiles}); if(state.cat==='profiles'){ viewProfiles(); applyBanner(); } });
    });
    document.getElementById('profSave').onclick=saveCurrentProfile;
  }
  // Shared by the Profiles view button and the dock save orb.
  function saveCurrentProfile(){
    const name=prompt('Profile name','Profile '+(state.profiles.length+1));
    if(!name) return;
    state.profiles.push(captureProfile(name));
    send({type:'saveProfiles', profiles:state.profiles});
    if(state.cat==='profiles'){ viewProfiles(); applyBanner(); }
  }
  function applyProfiles(list){ state.profiles = Array.isArray(list)?list:[]; if(state.surface==='menubar'){ renderMenubar(); return; } if(state.cat==='profiles'){ viewProfiles(); applyBanner(); } }

  function pushActivity(message, level){
    const d=new Date();
    const t=`${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}:${String(d.getSeconds()).padStart(2,'0')}`;
    state.activity.unshift({ time:t, message, level:level||'info' });
    if(state.activity.length>60) state.activity.length=60;
    announceSR(message);
    if(state.cat==='activity'){ viewActivity(); applyBanner(); }
  }
  // Screen-reader-only polite announcement, independent of which view is on
  // screen. Setting textContent (rather than appending) is enough to trigger
  // an announcement each call since the message text normally differs.
  function announceSR(message){
    const el=document.getElementById('srLive');
    if(el) el.textContent = message;
  }
  function viewActivity(){
    const rows = state.activity.map(a=>{
      const color = a.level==='error' ? '#ff8a73' : a.level==='warn' ? '#ffd9a0' : 'rgba(255,255,255,.85)';
      return `<div class="step" style="color:${color}">${esc(a.message)} <span>${a.time}</span></div>`;
    }).join('');
    content.innerHTML=
      `<div class="group"><h4>Activity</h4>
        <div class="reclist">${rows || '<div class="step" style="opacity:.7">Nothing yet. Start something and it will show up here.</div>'}</div>
        <div class="row"><button class="btn-reset" id="actClear">Clear</button></div>
      </div>`;
    const c=document.getElementById('actClear'); if(c) c.onclick=()=>{ state.activity=[]; viewActivity(); applyBanner(); };
  }

  function viewHotkeys(){
    const h=state.hotkeys;
    const row=(action,label,hint)=>`<div class="row"><span class="lab">${label}</span>`+
      `<button class="keycap" data-action="${action}">${comboGlyphs(h[action])}</button>`+
      (hint?`<span class="hint">${hint}</span>`:'')+`</div>`;
    content.innerHTML=
      `<div class="group"><h4>Global Shortcuts</h4>`+
        row('startStop','Start / Stop','press anywhere to toggle')+
        row('pickPosition','Pick position','')+
        row('toggleJiggler','Toggle jiggler','')+
        row('panic','Panic / kill','instantly halts all automation')+
      `</div>`+
      `<div class="group"><h4>Behavior</h4>`+
        `<div class="row"><span class="lab">Click a key, then press the new combination. Esc cancels.</span></div>`+
        `<div class="row"><button class="btn-reset" id="hkReset">Reset to defaults</button></div>`+
      `</div>`;
    content.querySelectorAll('.keycap').forEach(k=>k.onclick=()=>beginCapture(k));
    const reset=content.querySelector('#hkReset');
    if(reset) reset.onclick=resetHotkeys;
  }

  // Render a combo token string ("ctrl+opt+KeyP") into spaced keycap glyphs.
  function comboGlyphs(token){
    if(!token) return '?';
    const mod={ctrl:'⌃',opt:'⌥',shift:'⇧',cmd:'⌘'};
    const special={Escape:'⎋',Space:'Space',Tab:'⇥',Backspace:'⌫',
      ArrowUp:'↑',ArrowDown:'↓',ArrowLeft:'←',ArrowRight:'→',
      Minus:'-',Equal:'=',BracketLeft:'[',BracketRight:']',Backslash:'\\',
      Semicolon:';',Quote:"'",Comma:',',Period:'.',Slash:'/',Backquote:'`'};
    return token.split('+').map(t=>{
      if(mod[t]) return mod[t];
      if(special[t]) return special[t];
      if(/^Key([A-Z])$/.test(t)) return t.slice(3);
      if(/^Digit([0-9])$/.test(t)) return t.slice(5);
      return esc(t); // F1..F12 and anything else, shown literally
    }).join(' ');
  }

  // Live capture of a new combo on a clicked keycap.
  let capturing=null;
  var keyCaptureHandler=null;
  function beginCapture(btn){
    if(capturing) endCapture(true);
    capturing={btn, action:btn.dataset.action, prev:btn.innerHTML};
    btn.textContent='press a key…';
    btn.classList.add('capturing');
    document.addEventListener('keydown', onCaptureKey, true);
  }
  function endCapture(restore){
    if(!capturing) return;
    document.removeEventListener('keydown', onCaptureKey, true);
    if(restore) capturing.btn.innerHTML=capturing.prev;
    capturing.btn.classList.remove('capturing');
    capturing=null;
  }
  function onCaptureKey(e){
    if(!capturing || !document.contains(capturing.btn)){ endCapture(true); return; }
    e.preventDefault(); e.stopPropagation();
    const code=e.code;
    // Ignore lone modifier / caps-lock presses; wait for a real key.
    if(/^(Control|Shift|Alt|Meta)(Left|Right)$/.test(code) || code==='CapsLock') return;
    const mods=[];
    if(e.ctrlKey) mods.push('ctrl');
    if(e.altKey)  mods.push('opt');
    if(e.shiftKey)mods.push('shift');
    if(e.metaKey) mods.push('cmd');
    // Bare Escape cancels. Escape WITH modifiers is a valid combo (e.g. panic).
    if(code==='Escape' && mods.length===0){ endCapture(true); return; }
    const action=capturing.action;
    endCapture(false); // leave "press a key…" until the controller echoes back
    send({type:'setHotkey', action, combo:[...mods, code].join('+')});
  }
  function resetHotkeys(){
    // Defaults live with HotkeyManager in Swift; the controller echoes the
    // restored bindings back via the hotkeys event.
    send({type:'resetHotkeys'});
  }

  function viewMore(){
    const p=state.prefs;
    content.innerHTML=`
      <div class="group"><h4>General</h4>
        <div class="row"><span class="lab">Launch at login</span><div class="toggle ${p.launchAtLogin?'on':''}" id="m1"><div class="knob"></div></div></div>
        <div class="row"><span class="lab">Menu-bar mode</span><div class="toggle ${p.menuBarOnly?'on':''}" id="m2"><div class="knob"></div></div>
          <span class="hint">run quietly from the macOS menu bar</span></div>
        <div class="row"><span class="lab">Sound on click</span><div class="toggle ${p.soundOnClick?'on':''}" id="m3"><div class="knob"></div></div></div>
      </div>
      <div class="group"><h4>Appearance</h4>
        <div class="row"><span class="lab">Skin</span>
          <div class="skins" id="skinPick">
            <div class="swatch red ${p.skin==='red'?'sel':''}" data-skin="red" title="Nero Red"></div>
            <div class="swatch cobalt ${p.skin==='cobalt'?'sel':''}" data-skin="cobalt" title="Cobalt"></div>
            <div class="swatch graphite ${p.skin==='graphite'?'sel':''}" data-skin="graphite" title="Graphite"></div>
            <div class="swatch emerald ${p.skin==='emerald'?'sel':''}" data-skin="emerald" title="Emerald"></div>
          </div></div>
      </div>
      <div class="group"><h4>About</h4>
        <div class="row"><span class="hint">fiddle, a loving tribute to Nero StartSmart. Nero fiddled while Rome burned, fiddle fiddles with your mouse while you are away. Accessibility permission required on first launch.</span></div>
      </div>`;
    toggle('m1', v=>{ p.launchAtLogin=v; send({type:'setPref', key:'launchAtLogin', value:v}); });
    toggle('m2', v=>{ p.menuBarOnly=v;   send({type:'setPref', key:'menuBarOnly',   value:v}); });
    toggle('m3', v=>{ p.soundOnClick=v;  send({type:'setPref', key:'soundOnClick',  value:v}); });
    content.querySelectorAll('#skinPick .swatch').forEach(s=>s.onclick=()=>{
      const name=s.dataset.skin;
      state.prefs.skin=name;
      applySkin(name);
      content.querySelectorAll('#skinPick .swatch').forEach(x=>x.classList.toggle('sel', x===s));
      send({type:'setPref', key:'skin', value:name});
    });
  }

  function viewSimple(){
    const tab=state.simpleTab, c=state.clicker, j=state.jiggler;
    const body = tab==='click'
      ? `<div class="group"><h4>Click Rate</h4>
          <div class="row"><span class="lab">Click</span>
            <input class="field" id="sc-rate" value="${c.rate}" aria-label="Click rate"><span class="hint">times per</span>
            <select class="field" id="sc-unit" aria-label="Rate unit"><option value="second" ${c.rateUnit==='second'?'selected':''}>second</option><option value="minute" ${c.rateUnit==='minute'?'selected':''}>minute</option></select></div></div>`
      : `<div class="group"><h4>Jiggle Interval</h4>
          <div class="row"><span class="lab">Every</span>
            <input class="field" id="sj-s" value="${j.secs}" aria-label="Jiggle interval in seconds"><span class="hint">seconds</span></div></div>`;
    content.innerHTML=
      `<div class="group"><h4>Mode</h4>
        <div class="row"><div class="seg" id="simpleTab">
          <button data-v="click" class="${tab==='click'?'on':''}">Auto Click</button>
          <button data-v="jiggle" class="${tab==='jiggle'?'on':''}">Jiggle</button></div></div>
      </div>` + body +
      `<div class="group"><h4>Run</h4>
        <div class="row"><span class="hint">Press the flame to ${tab==='click'?'click at the cursor':'jiggle'}, again to stop. Or use the panic key.</span></div>
      </div>`;
    seg('simpleTab', v=>{ state.simpleTab=v; send({type:'setPref', key:'lastMode', value: v==='jiggle'?'jiggler':'clicker'}); viewSimple(); applyBanner(); });
    if(tab==='click'){ bind('sc-rate', v=>{c.rate=Math.max(1,+v||1); persist();}); bindSel('sc-unit', v=>{c.rateUnit=v; persist();}); }
    else { bind('sj-s', v=>{j.secs=+v||0; persist();}); }
  }

  function viewMenubar(){
    const tab=state.simpleTab, c=state.clicker, j=state.jiggler, adv=state.prefs.interfaceMode!=='simple';
    const interval = tab==='click'
      ? `<div class="row"><span class="lab">Click</span>
          <input class="field" id="mc-rate" value="${c.rate}" aria-label="Click rate"><span class="hint">per</span>
          <select class="field" id="mc-unit" aria-label="Rate unit"><option value="second" ${c.rateUnit==='second'?'selected':''}>sec</option><option value="minute" ${c.rateUnit==='minute'?'selected':''}>min</option></select></div>`
      : `<div class="row"><span class="lab">Every</span>
          <input class="field" id="mj-s" value="${j.secs}" aria-label="Jiggle interval in seconds"><span class="hint">seconds</span></div>`;
    let quick = '';
    if(adv){
      const profOpts = (state.profiles||[]).map(p=>`<button class="btn-reset" data-applyprof="${esc(p.id)}">${esc(p.name)}</button>`).join(' ');
      const macroOpts = (state.macros||[]).map(m=>`<button class="btn-reset" data-playmac="${esc(m.id)}">${esc(m.name)}</button>`).join(' ');
      quick =
        `<div class="group"><h4>Quick</h4>
          <div class="row"><span class="lab">Profiles</span><span class="hint">${profOpts||'none'}</span></div>
          <div class="row"><span class="lab">Macros</span><span class="hint">${macroOpts||'none'}</span></div>
        </div>`;
    }
    content.innerHTML=
      `<div class="group"><h4>Mode</h4>
        <div class="row"><div class="seg" id="mTab">
          <button data-v="click" class="${tab==='click'?'on':''}">Auto Click</button>
          <button data-v="jiggle" class="${tab==='jiggle'?'on':''}">Jiggle</button></div></div>
        ${interval}
      </div>` + quick +
      `<div class="group"><h4>Window</h4>
        <div class="row"><button class="btn-reset" id="mOpen">Open fiddle</button>
          <button class="btn-reset" id="mQuit">Quit</button></div>
      </div>`;
    seg('mTab', v=>{ state.simpleTab=v; send({type:'setPref', key:'lastMode', value: v==='jiggle'?'jiggler':'clicker'}); viewMenubar(); applyBanner(); });
    if(tab==='click'){ bind('mc-rate', v=>{c.rate=Math.max(1,+v||1); persist();}); bindSel('mc-unit', v=>{c.rateUnit=v; persist();}); }
    else { bind('mj-s', v=>{j.secs=+v||0; persist();}); }
    document.getElementById('mOpen').onclick=()=>send({type:'window', action:'showWindow'});
    document.getElementById('mQuit').onclick=()=>send({type:'window', action:'quit'});
    content.querySelectorAll('[data-applyprof]').forEach(b=>b.onclick=()=>send({type:'applyProfile', id:b.dataset.applyprof}));
    content.querySelectorAll('[data-playmac]').forEach(b=>b.onclick=()=>send({type:'start', mode:'macro', config:{macroId:b.dataset.playmac, repeat:'until', times:1}}));
  }

  function setMode(mode){
    state.prefs.interfaceMode = mode;
    send({type:'setPref', key:'interfaceMode', value:mode});
    applyMode(mode);
  }

  function applyMode(mode){
    const simple = mode==='simple';
    document.body.dataset.mode = simple ? 'simple' : 'advanced';
    if(simple){
      document.getElementById('catTitle').innerHTML = 'Simple mode';
      document.getElementById('catSub').innerHTML = 'Auto Click and Jiggle';
      viewSimple();
      applyBanner();
    } else {
      selectCat(state.cat || 'home');
    }
    const mt=document.getElementById('modeToggle');
    if(mt) mt.querySelectorAll('button').forEach(b=>{
      const on=b.dataset.v===(simple?'simple':'advanced');
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    // The window only auto-fits on load, so ask it to re-fit after the layout reflows.
    setTimeout(()=>send({type:'window', action:'fit'}), 40);
  }

  // ---------- helpers ----------
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function opt(arr,sel){return arr.map(a=>`<option ${a===sel?'selected':''}>${a}</option>`).join('')}
  function bind(id,fn){const el=document.getElementById(id);if(el)el.oninput=e=>fn(e.target.value)}
  function bindSel(id,fn){const el=document.getElementById(id);if(el)el.onchange=e=>fn(e.target.value)}
  // Segmented button groups (e.g. Single/Double, Zen/Visible). The buttons are
  // real <button>s already, so Tab/Enter/Space work for free; this exposes
  // which one is selected to assistive tech via aria-pressed and role="group".
  function seg(id,fn){
    const w=document.getElementById(id);if(!w)return;
    w.setAttribute('role','group');
    const buttons=w.querySelectorAll('button');
    buttons.forEach(b=>b.setAttribute('aria-pressed', b.classList.contains('on') ? 'true' : 'false'));
    buttons.forEach(b=>b.onclick=()=>{
      buttons.forEach(x=>{x.classList.remove('on'); x.setAttribute('aria-pressed','false');});
      b.classList.add('on'); b.setAttribute('aria-pressed','true');
      fn(b.dataset.v);
    });
  }
  // Custom toggle switches (divs styled as switches). Give them switch
  // semantics, a label (borrowed from the adjacent .lab text), and Space/Enter
  // activation, since a div has none of that for free.
  function toggle(id,fn){
    const t=document.getElementById(id);if(!t)return;
    t.setAttribute('role','switch');
    t.setAttribute('tabindex','0');
    t.setAttribute('aria-checked', t.classList.contains('on') ? 'true' : 'false');
    if(!t.hasAttribute('aria-label')){
      const row=t.closest('.row');
      const lab=row && row.querySelector('.lab');
      if(lab) t.setAttribute('aria-label', lab.textContent.trim());
    }
    const activate=()=>{
      t.classList.toggle('on');
      const on=t.classList.contains('on');
      t.setAttribute('aria-checked', on ? 'true' : 'false');
      fn(on);
    };
    t.onclick=activate;
    t.onkeydown=e=>{ if(e.key===' ' || e.key==='Enter'){ e.preventDefault(); activate(); } };
  }

  function taskMouse(){return '<svg viewBox="0 0 48 48"><defs><linearGradient id="t1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fafbff"/><stop offset="1" stop-color="#9aa6bd"/></linearGradient></defs><rect x="14" y="5" width="20" height="38" rx="10" fill="url(#t1)" stroke="#4a5364" stroke-width="1.4"/><rect x="22.5" y="8" width="3" height="12" rx="1.5" fill="#4a5364"/><ellipse cx="24" cy="15" rx="7" ry="9" fill="rgba(255,255,255,.45)"/></svg>'}
  function taskJiggle(){return '<svg viewBox="0 0 48 48"><defs><linearGradient id="t2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a9e7ff"/><stop offset="1" stop-color="#1f7fbf"/></linearGradient></defs><path d="M5 24h38M5 24l9-8M5 24l9 8M43 24l-9-8M43 24l-9 8" fill="none" stroke="url(#t2)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>'}
  function taskRec(){return '<svg viewBox="0 0 48 48"><defs><radialGradient id="t3" cx="38%" cy="30%" r="75%"><stop offset="0" stop-color="#ff8a73"/><stop offset="1" stop-color="#a30b07"/></radialGradient></defs><circle cx="24" cy="24" r="19" fill="none" stroke="#e8d9a0" stroke-width="3.5"/><circle cx="24" cy="24" r="11" fill="url(#t3)" stroke="#5a0303"/></svg>'}
  function taskKey(){return '<svg viewBox="0 0 48 48"><defs><linearGradient id="t4" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3f4f6"/><stop offset="1" stop-color="#9aa0a8"/></linearGradient></defs><rect x="4" y="13" width="40" height="24" rx="4" fill="url(#t4)" stroke="#4a5364" stroke-width="1.4"/><g fill="#4a5364"><rect x="9" y="18" width="6" height="5" rx="1"/><rect x="18" y="18" width="6" height="5" rx="1"/><rect x="27" y="18" width="6" height="5" rx="1"/><rect x="9" y="27" width="6" height="5" rx="1"/><rect x="18" y="27" width="21" height="5" rx="1"/></g></svg>'}

  const views={home:viewHome,clicker:viewClicker,jiggler:viewJiggler,wakelock:viewWakeLock,antiafk:viewAntiAFK,recorder:viewRecorder,hotkeys:viewHotkeys,more:viewMore,sequencer:viewSequencer,macro:viewMacroPlayer,profiles:viewProfiles,activity:viewActivity};

  function applyClickerTitle(){
    if(state.cat!=='clicker') return;
    document.getElementById('catTitle').innerHTML = state.device==='keyboard' ? 'Auto Presser' : 'Auto Clicker';
    document.getElementById('catSub').innerHTML   = state.device==='keyboard' ? 'Press a key on a fixed interval' : 'Configure automated clicking';
  }

  function selectCat(cat, fromUser){
    if(typeof endCapture==='function') endCapture(true);
    if(keyCaptureHandler){ document.removeEventListener('keydown', keyCaptureHandler, true); keyCaptureHandler=null; }
    state.cat=cat;
    if(fromUser){
      // Only real automation categories count as a "last used" mode; home,
      // hotkeys, more, profiles and activity are navigation, not modes.
      const catMode={clicker:'clicker', jiggler:'jiggler', wakelock:'wakeLock', antiafk:'antiAFK', recorder:'recorder', sequencer:'macro', macro:'macro'}[cat];
      if(catMode) send({type:'setPref', key:'lastMode', value: cat==='clicker'&&state.device==='keyboard' ? 'keyboard' : catMode});
    }
    document.querySelectorAll('.cat').forEach(c=>{
      const active=c.dataset.cat===cat;
      c.classList.toggle('active',active);
      if(active) c.setAttribute('aria-current','true'); else c.removeAttribute('aria-current');
    });
    document.querySelectorAll('.app').forEach(a=>{
      const on=a.dataset.cat===cat;
      a.classList.toggle('on',on);
      if(on) a.setAttribute('aria-current','true'); else a.removeAttribute('aria-current');
    });
    document.getElementById('catTitle').innerHTML=titles[cat][0];
    document.getElementById('catSub').innerHTML=titles[cat][1];
    applyClickerTitle();
    views[cat]();
    applyBanner(); // re-add the permission banner; views[cat]() replaced #content
  }

  document.querySelectorAll('.cat[data-cat]').forEach(c=>c.onclick=()=>selectCat(c.dataset.cat, true));
  document.querySelectorAll('.app[data-cat]').forEach(a=>a.onclick=()=>selectCat(a.dataset.cat, true));
  // The Applications list items are divs (role="button"), so Enter/Space do
  // not activate them natively; #applist is never rebuilt (only .cat/.app
  // classes toggle), so one delegated listener covers every item.
  const applistEl=document.getElementById('applist');
  if(applistEl) applistEl.addEventListener('keydown', e=>{
    const item=e.target.closest('.app');
    if(!item) return;
    if(e.key==='Enter' || e.key===' '){ e.preventDefault(); item.click(); }
  });

  // ---------- start / stop (engine driven) ----------
  const btn=document.getElementById('startBtn'),
        led=document.getElementById('led'),
        statusText=document.getElementById('statusText');

  // The button only SENDS intent. The glow + LED follow the engine's status event.
  btn.onclick=()=>{
    if(state.running){ send({type:'stop'}); return; }
    const m=currentMode();
    const cfg=currentConfig(m);
    // Simple mode and the popover have no position controls and promise
    // clicks at the cursor. Override for this start only; updateConfig and
    // profiles keep the position the user actually picked, so the override
    // must not live inside clickerConfig().
    if(m==='clicker' && (state.surface==='menubar' || state.prefs.interfaceMode==='simple')) cfg.position='current';
    send({type:'start', mode:m, config:cfg});
  };

  function setStatus(value){
    state.running = (value === 'running');
    btn.classList.toggle('running', state.running);
    btn.setAttribute('aria-pressed', state.running ? 'true' : 'false');
    led.classList.toggle('live', state.running);
    statusText.textContent = state.running ? 'Running' : 'Idle';
    if(state.surface==='menubar'){ renderMenubar(); return; }
  }

  let needsAccessibility = false;

  function renderPermissions(p){
    needsAccessibility = !(p && p.accessibility);
    state.inputMonitoring = !!(p && p.inputMonitoring);
    applyBanner();
    if(state.cat==='recorder'){ viewRecorder(); applyBanner(); }
  }

  // ---------- undo toast (forgiveness for destructive one-click actions) ----------
  // One slot: a new destructive action finalizes any pending one first.
  let undoState=null; // {label, onUndo, onExpire, timer}
  function showUndo(label, onUndo, onExpire){
    finalizeUndo();
    let bar=document.getElementById('undobar');
    if(!bar){
      bar=document.createElement('div'); bar.id='undobar';
      document.body.appendChild(bar);
    }
    bar.hidden=false;
    bar.innerHTML=`<span>${esc(label)}</span><button id="undoBtn">Undo</button>`;
    document.getElementById('undoBtn').onclick=()=>{
      const u=undoState; undoState=null; clearTimeout(u.timer);
      bar.hidden=true; u.onUndo();
    };
    undoState={label, onUndo, onExpire, timer:setTimeout(()=>{ finalizeUndo(); }, 6000)};
  }
  function finalizeUndo(){
    if(!undoState) return;
    const u=undoState; undoState=null; clearTimeout(u.timer);
    const bar=document.getElementById('undobar'); if(bar) bar.hidden=true;
    if(u.onExpire) u.onExpire();
  }
  window.addEventListener('pagehide', finalizeUndo);

  // The scroll content (#content) is absolutely positioned, so the banner must
  // live INSIDE it as the first child to push the task list down rather than
  // float over it. #content is rebuilt on every view change, so this re-runs
  // after each render.
  function applyBanner(){
    const host=document.getElementById('content');
    if(!host) return;
    let bar=document.getElementById('permbar');
    if(!needsAccessibility){ if(bar) bar.remove(); return; }
    if(!bar){
      bar=document.createElement('div');
      bar.id='permbar';
      bar.innerHTML='Accessibility permission is required to control the mouse. <b>Open System Settings →</b>';
      bar.onclick=()=>send({type:'openSettings', pane:'accessibility'});
      // Gate the one-shot entrance: after it finishes once, later re-inserts
      // (every view render while permission is missing) must not replay it.
      bar.addEventListener('animationend', ()=>{ bar.dataset.entered='1'; }, {once:true});
    }
    if(host.firstChild !== bar) host.insertBefore(bar, host.firstChild);
  }

  function onPositionPicked(x,y,purpose){
    if(purpose==='step'){
      // A sequencer-step pick. Only the surface that asked for it (its
      // pendingPick is set) applies it; the other surface must not treat a
      // broadcast step pick as a clicker fixed position.
      if(state.pendingPick){
        state.pendingPick=null;
        const ax=document.getElementById('addX'), ay=document.getElementById('addY');
        if(ax) ax.value=x; if(ay) ay.value=y;
      }
      return;
    }
    state.pendingPick=null;
    const c=state.clicker;
    c.x=x; c.y=y; c.pos='pick';
    if(state.cat==='clicker'){
      const px=document.getElementById('px'), py=document.getElementById('py');
      if(px) px.value=x;
      if(py) py.value=y;
      const pr=document.querySelector('input[name=pos][value=pick]');
      if(pr) pr.checked=true;
    }
  }

  // Apply a saved config pushed from Swift (on ready), reflecting persisted
  // state back into the form. Mirrors the wire shapes in Protocol.swift.
  function applyConfig(mode, cfg){
    if(!cfg) return;
    if(mode==='clicker'){
      // Math.round, not |0: bitwise ops wrap at 2^31, corrupting the restored
      // form for intervals over ~24.8 days.
      const c=state.clicker, total=Math.max(0, Math.round(+cfg.intervalMs||0));
      c.ms = total%1000;
      const totalSec=Math.floor(total/1000);
      c.sec = totalSec%60;
      const totalMin=Math.floor(totalSec/60);
      c.min = totalMin%60;
      c.hrs = Math.floor(totalMin/60);
      c.button = cfg.button ? cfg.button.charAt(0).toUpperCase()+cfg.button.slice(1) : c.button;
      c.type = cfg.clickType==='double' ? 'Double' : 'Single';
      c.repeat = cfg.repeat==='times' ? 'times' : 'until';
      c.times = Math.round(+cfg.times||0);
      c.pos = cfg.position==='fixed' ? 'pick' : 'current';
      c.x = Math.round(+cfg.x||0); c.y = Math.round(+cfg.y||0);
      if(cfg.rate)     c.rate = Math.max(1, Math.round(+cfg.rate||0));
      if(cfg.rateUnit) c.rateUnit = cfg.rateUnit==='second' ? 'second' : 'minute';
    } else if(mode==='jiggler'){
      const j=state.jiggler;
      j.secs = Math.round(+cfg.intervalSec||0);
      j.dist = Math.round(+cfg.distancePx||0);
      j.mode = cfg.mode==='visible' ? 'Visible' : 'Zen';
      j.wake = !!cfg.keepAwake;
      j.idleOnly = !!cfg.idleOnly;
    } else if(mode==='wakeLock'){
      state.wakelock.keepDisplay = !!cfg.keepDisplayAwake;
      state.wakelock.keepSystem  = !!cfg.keepSystemAwake;
      if(state.cat==='wakelock') viewWakeLock();
    } else if(mode==='antiAFK'){
      state.antiafk.secs = Math.round(+cfg.intervalSec||0);
      state.antiafk.dist = Math.round(+cfg.distancePx||0);
      state.antiafk.keepAwake = !!cfg.keepAwake;
      if(state.cat==='antiafk') viewAntiAFK();
    } else if(mode==='keyboard'){
      const k=state.keyboard, total=Math.max(0, Math.round(+cfg.intervalMs||0));
      k.ms = total%1000; const ts=Math.floor(total/1000); k.sec=ts%60; const tm=Math.floor(ts/60); k.min=tm%60; k.hrs=Math.floor(tm/60);
      k.combo = cfg.combo || 'Space';
      k.repeat = cfg.repeat==='times' ? 'times' : 'until';
      k.times = Math.round(+cfg.times||0) || 50;
      if(state.cat==='clicker' && state.device==='keyboard') viewKeyboard();
    } else if(mode==='recorder'){
      state.recorder.repeat = cfg.repeat==='times' ? 'times' : 'until';
      state.recorder.times = Math.round(+cfg.times||0) || 1;
    }
    if(state.surface==='menubar'){ renderMenubar(); return; }
    if(state.cat===mode && views[mode]) views[mode](); // re-render if showing this mode
  }

  // Theme the whole UI by flipping the --ac-* CSS variables via a body attribute.
  function applySkin(name){
    const next = name || 'red';
    const changed = document.body.dataset.skin !== next;
    document.body.dataset.skin = next;
    // Rebuild the popover only when the skin actually changed; otherwise an
    // unrelated prefs broadcast rebuilds its form mid-use.
    if(changed && state.surface==='menubar'){ renderMenubar(); return; }
  }

  // The saved last-used mode may move the visible view only once, at boot.
  // Later prefs broadcasts (profile applies, edits on the other surface)
  // must not yank the view the user is looking at.
  let lastModeRestored = false;

  let prefsApplied = false;
  function applyPrefs(p){
    if(!p) return;
    // Re-render only what a changed pref actually affects. Prefs broadcasts
    // arrive for unrelated records too (for example the other surface noting
    // lastMode), and an unconditional rebuild yanks the form mid-use.
    const first = !prefsApplied; prefsApplied = true;
    const prevSkin = state.prefs.skin, prevMode = state.prefs.interfaceMode, prevDevice = state.device;
    state.prefs.launchAtLogin = !!p.launchAtLogin;
    state.prefs.menuBarOnly   = !!p.menuBarOnly;
    state.prefs.soundOnClick  = !!p.soundOnClick;
    state.prefs.skin = p.skin || 'red';
    state.prefs.interfaceMode = p.interfaceMode || 'advanced';
    if(!lastModeRestored){
      lastModeRestored = true;
      const lm = p.lastMode || 'clicker';
      state.simpleTab = lm==='jiggler' ? 'jiggle' : 'click';
      if(state.surface!=='menubar'){
        // keyboard lives under the clicker category (the Device pill,
        // restored separately from prefs.device, flips it). An unknown
        // value maps to nothing and leaves the default category alone.
        const cat=({clicker:'clicker', jiggler:'jiggler', wakeLock:'wakelock', antiAFK:'antiafk', recorder:'recorder', macro:'macro', keyboard:'clicker'})[lm];
        if(cat) state.cat = cat;
      }
    }
    applySkin(state.prefs.skin);
    if(state.surface==='menubar'){
      if(first){ renderMenubar(); }
      return;
    }
    if(state.cat==='more') viewMore();
    state.device = p.device || 'mouse';
    const dv=document.getElementById('deviceValue'); if(dv) dv.textContent = state.device==='keyboard' ? 'Keyboard' : 'Mouse';
    const dm=document.getElementById('deviceMenu');
    if(dm) dm.querySelectorAll('li').forEach(li=>li.classList.toggle('on', li.dataset.value===state.device));
    if(state.cat==='clicker' && (first || prevDevice!==state.device || prevSkin!==state.prefs.skin)){ applyClickerTitle(); views.clicker(); applyBanner(); }
    if(first || prevMode!==state.prefs.interfaceMode) applyMode(state.prefs.interfaceMode);
  }

  function applyHotkeys(bindings){
    if(!bindings) return;
    state.hotkeys=Object.assign({}, state.hotkeys, bindings);
    if(state.cat==='hotkeys'){ viewHotkeys(); applyBanner(); }
  }

  function applyRecording(e){
    state.recordingActive = !!e.active;
    state.recording = e.steps || [];
    if(state.cat==='recorder'){ viewRecorder(); applyBanner(); }
  }

  function applyMacros(list){
    state.macros = Array.isArray(list) ? list : [];
    if(state.selectedMacro && !state.macros.find(m=>m.id===state.selectedMacro)) state.selectedMacro = null;
    if(state.surface==='menubar'){ renderMenubar(); return; }
    rerenderMacroViews();
  }

  // ---------- inbound events (Swift -> web) ----------
  window.fiddleEvent=function(e){
    try{
      switch(e && e.type){
        case 'status':         setStatus(e.value); break;
        case 'permissions':    renderPermissions(e); break;
        case 'positionPicked': onPositionPicked(e.x, e.y, e.purpose); break;
        case 'config':         applyConfig(e.mode, e.config); break;
        case 'prefs':          applyPrefs(e); break;
        case 'hotkeys':        applyHotkeys(e.bindings); break;
        case 'recording':      applyRecording(e); break;
        case 'macros':         applyMacros(e.list); break;
        case 'profiles':       applyProfiles(e.list); break;
        case 'log':            pushActivity(e.message, e.level); break;
        case 'error':          console.error('[fiddle]', e.message); pushActivity(e.message, 'error'); break;
      }
    }catch(err){ console.error('[fiddle] event handler failed', err); }
  };

  // ---------- window orbs (?  -  x) ----------
  (function(){
    const wb=document.querySelectorAll('.winbtn'); // DOM order: help, minimize, close
    if(wb[0]) wb[0].onclick=()=>send({type:'window', action:'help'});
    if(wb[1]) wb[1].onclick=()=>send({type:'window', action:'minimize'});
    if(wb[2]) wb[2].onclick=()=>send({type:'window', action:'close'});
    // These are divs styled as round orb buttons, not native <button>s, so
    // Enter/Space do not activate them for free; wire that up.
    wb.forEach(b=>b.addEventListener('keydown', e=>{
      if(e.key==='Enter' || e.key===' '){ e.preventDefault(); b.click(); }
    }));
  })();

  // ---------- device selector (custom themed dropdown) ----------
  // Clicking anywhere on the pill toggles a themed menu; keyboard modes are
  // Phase 2 so they are shown but disabled.
  (function(){
    const pill=document.getElementById('deviceSel');
    const menu=document.getElementById('deviceMenu');
    const valueEl=document.getElementById('deviceValue');
    if(!pill || !menu) return;

    const close=()=>{ menu.hidden=true; pill.classList.remove('open'); };
    const open =()=>{ menu.hidden=false; pill.classList.add('open'); };

    pill.addEventListener('click', e=>{
      if(e.target.closest('.sel-menu')) return; // item clicks handled below
      menu.hidden ? open() : close();
      e.stopPropagation();
    });
    pill.addEventListener('keydown', e=>{
      if(e.key==='Enter' || e.key===' '){ e.preventDefault(); menu.hidden ? open() : close(); }
      else if(e.key==='Escape'){ close(); }
    });

    menu.querySelectorAll('li').forEach(li=>{
      li.addEventListener('click', e=>{
        e.stopPropagation();
        if(li.classList.contains('disabled')) return;
        menu.querySelectorAll('li').forEach(x=>x.classList.remove('on'));
        li.classList.add('on');
        valueEl.textContent = li.dataset.value === 'mouse' ? 'Mouse'
                            : li.dataset.value === 'keyboard' ? 'Keyboard' : 'Mouse + Keyboard';
        close();
        const dev = li.dataset.value; // 'mouse' or 'keyboard'
        if(dev === 'mouse' || dev === 'keyboard'){
          state.device = dev;
          send({type:'setPref', key:'device', value:dev});
          // The device pill changes what the clicker view (and the Start/Stop
          // hotkey) drives; keep lastMode aimed at what the UI now shows.
          if(state.cat==='clicker'){
            send({type:'setPref', key:'lastMode', value: dev==='keyboard' ? 'keyboard' : 'clicker'});
            applyClickerTitle(); views.clicker(); applyBanner();
          }
        }
      });
    });

    document.addEventListener('click', ()=>{ if(!menu.hidden) close(); });
  })();

  // ---------- dock save orb ----------
  (function(){
    const save=document.querySelector('.miniorb.save');
    if(save){
      save.onclick=saveCurrentProfile;
      save.addEventListener('keydown', e=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); save.click(); } });
    }
  })();

  // ---------- About overlay (info orb) + external links ----------
  (function(){
    const overlay=document.getElementById('aboutOverlay');
    const info=document.querySelector('.miniorb.info');
    if(info && overlay){
      info.style.cursor='pointer';
      info.onclick=()=>{ overlay.hidden=false; };
      info.addEventListener('keydown', e=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); info.click(); } });
      document.getElementById('aboutClose').onclick=()=>{ overlay.hidden=true; };
      document.getElementById('aboutGh').onclick=()=>{ overlay.hidden=true; send({type:'window', action:'help'}); };
      const upd=document.getElementById('aboutUpdate');
      if(upd) upd.onclick=()=>{ overlay.hidden=true; send({type:'window', action:'checkForUpdates'}); };
      overlay.addEventListener('click', e=>{ if(e.target===overlay) overlay.hidden=true; });
    }
    // Show the real app version (injected by the native bridge).
    const ver=document.getElementById('aboutVer');
    if(ver && window.__fiddleVersion) ver.textContent = window.__fiddleVersion;
    const footVer=document.querySelector('.footer .ver');
    if(footVer && window.__fiddleVersion) footVer.textContent = 'fiddle ' + window.__fiddleVersion + ' · for macOS';
    const modeToggle=document.getElementById('modeToggle');
    if(modeToggle) modeToggle.querySelectorAll('button').forEach(b=>b.onclick=()=>setMode(b.dataset.v));
  })();

  // ---------- boot ----------
  if(window.__fiddleSurface==='menubar' || location.search.indexOf('surface=menubar')>=0){ state.surface='menubar'; document.body.dataset.surface='menubar'; }
  if(state.surface==='menubar'){
    viewMenubar();
    applyBanner();
  } else {
    selectCat('home');
  }
  send({type:'ready'});
  send({type:'checkPermissions'});
