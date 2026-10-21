extends RefCounted

# A portable local review artifact. No server, libraries, requests or uploads.
static func write_file(path: String, manifest: Dictionary) -> bool:
	# JSON is data in a script element: escaping '<' prevents a participant name
	# from closing it. Visible labels are always assigned through textContent.
	var data := JSON.stringify(manifest).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(HTML.replace("__SESSION_DATA__", data))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok


const HTML := """<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beacon Bay · Session voice</title>
<style>
:root{color-scheme:dark;font:16px system-ui,sans-serif;background:#101d26;color:#e9efef}body{max-width:840px;margin:40px auto;padding:0 20px}h1{font-size:28px;margin-bottom:8px}p{line-height:1.55;color:#b8cbcf}button,select{font:inherit;background:#223c49;color:inherit;border:1px solid #56737e;border-radius:8px;padding:9px 14px;cursor:pointer}button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #65d4bc}button[aria-pressed=true]{background:#35665f}.transport{display:flex;gap:14px;align-items:center;flex-wrap:wrap;padding:20px 0}#seek{width:100%;accent-color:#65d4bc}.speaker{display:flex;align-items:center;gap:12px;border:1px solid #3e5964;border-radius:12px;padding:16px;margin:12px 0}.identity{flex:1}.role{font-size:13px;color:#a1b7bf;margin-top:5px}.lamp{width:12px;height:12px;flex:none;border-radius:50%;background:#38505b}.speaker.active .lamp{background:#72e8bf;box-shadow:0 0 12px #72e8bf}.speaker.muted{opacity:.6}label{display:flex;align-items:center;gap:8px}#status{min-height:25px;color:#efc680}small{color:#a1b7bf}.levels{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
</style>
<h1>Session voice</h1><p id="session"></p>
<p>One conversation, with a separate synchronized track for every recorded player. Use <strong>Solo</strong> to hear one person clearly. Green dots show audio activity in each track.</p>
<div class="transport"><button id="play" type="button">Play session</button><button id="restart" type="button">Restart</button><output id="time" aria-live="off">0:00 / 0:00</output><input id="seek" type="range" min="0" max="0" value="0" step="0.02" aria-label="Session playback position"></div>
<div class="levels"><label for="levels">Jump to level</label><select id="levels"><option value="">Choose a recorded level</option></select></div>
<div id="speakers"></div><p id="status" role="status"></p>
<small>Keep this file beside session.json and the speaker WAV files. Recording pauses, players without recording permission, and missing packets are silent. Audio activity is a volume indicator, not a transcript.</small>
<script type="application/json" id="session-data">__SESSION_DATA__</script>
<script>
'use strict';
const session=JSON.parse(document.getElementById('session-data').textContent),rate=session.sample_rate||16000,duration=session.duration_s||0;
const seek=document.getElementById('seek'),play=document.getElementById('play'),time=document.getElementById('time'),status=document.getElementById('status'),tracks=[];
let playing=false,position=0,solo=null;
document.getElementById('session').textContent='Session '+(session.session_id||'')+' · '+(session.tracks||[]).length+' speaker tracks';
seek.max=duration;
const clock=s=>Math.floor(s/60)+':'+String(Math.floor(s%60)).padStart(2,'0');
function refresh(){time.textContent=clock(position)+' / '+clock(duration);seek.value=position;play.textContent=playing?'Pause session':'Play session';}
function pause(){playing=false;tracks.forEach(t=>t.audio.pause());refresh();}
function move(value){position=Math.max(0,Math.min(duration,Number(value)||0));tracks.forEach(t=>{t.audio.currentTime=position;});refresh();}
function updateMutes(){tracks.forEach(t=>{t.audio.muted=!t.enabled||(solo!==null&&solo!==t.id);t.row.classList.toggle('muted',t.audio.muted);t.solo.setAttribute('aria-pressed',String(solo===t.id));});}
for(const info of session.tracks||[]){
 const audio=new Audio(info.file);audio.preload='metadata';
 const row=document.createElement('div');row.className='speaker';
 const lamp=document.createElement('span');lamp.className='lamp';lamp.setAttribute('aria-hidden','true');row.append(lamp);
 const identity=document.createElement('div');identity.className='identity';
 const name=document.createElement('strong');name.textContent=info.display_name||info.speaker_id;identity.append(name);
 const role=document.createElement('div');role.className='role';role.textContent=(info.departments||[]).join(' + ')+' · '+info.speaker_id;identity.append(role);row.append(identity);
 const label=document.createElement('label'),enabled=document.createElement('input');enabled.type='checkbox';enabled.checked=true;label.append(enabled,document.createTextNode('Hear'));row.append(label);
 const button=document.createElement('button');button.type='button';button.textContent='Solo';button.setAttribute('aria-pressed','false');button.setAttribute('aria-label','Solo '+name.textContent);row.append(button);
 const track={id:info.speaker_id,audio,row,solo:button,enabled:true,activity:(session.audio_activity||[]).filter(s=>s.speaker_id===info.speaker_id)};
 enabled.addEventListener('change',()=>{track.enabled=enabled.checked;updateMutes();});
 button.addEventListener('click',()=>{solo=solo===track.id?null:track.id;updateMutes();});
 audio.addEventListener('error',()=>{status.textContent='A speaker file could not be opened. Keep this player in its original voice session folder.';pause();});
 tracks.push(track);document.getElementById('speakers').append(row);
}
for(const segment of session.level_segments||[]){
 const option=document.createElement('option');option.value=segment.start_frame/rate;
 option.textContent='Level '+(segment.level_id??segment.level_number??'?')+' · '+(segment.level_name||segment.level_run_id||'')+' · '+clock(segment.start_frame/rate);
 document.getElementById('levels').append(option);
}
document.getElementById('levels').addEventListener('change',event=>{if(event.target.value!=='')move(event.target.value);});
play.addEventListener('click',async()=>{
 if(playing){pause();return;}if(!tracks.length)return;if(position>=duration)move(0);
 status.textContent='';playing=true;refresh();
 try{await Promise.all(tracks.map(t=>{t.audio.currentTime=position;return t.audio.play();}));if(!playing)tracks.forEach(t=>t.audio.pause());}
 catch(error){pause();status.textContent='Playback could not start. Check that the speaker WAV files are present.';}
});
document.getElementById('restart').addEventListener('click',()=>move(0));seek.addEventListener('input',()=>move(seek.value));
function tick(){
 if(playing&&tracks.length){position=Math.min(duration,tracks[0].audio.currentTime);for(const t of tracks)if(Math.abs(t.audio.currentTime-position)>.12)t.audio.currentTime=position;if(position>=duration-.02)pause();}
 const frame=position*rate;for(const t of tracks)t.row.classList.toggle('active',playing&&!t.audio.muted&&t.activity.some(s=>frame>=s.start_frame&&frame<s.end_frame));refresh();requestAnimationFrame(tick);
}
if(!tracks.length){play.disabled=true;status.textContent='This session contains no recorded speakers.';}refresh();requestAnimationFrame(tick);
</script></html>
"""
