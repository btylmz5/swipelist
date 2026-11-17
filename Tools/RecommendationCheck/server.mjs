import assert from 'node:assert/strict';
import {accepts,validateV2,qualityBatch} from '../../supabase/functions/swipelist2-suggest-songs/quality.ts';
const conditions=[{id:'energy',dimension:'energy',value:'chill',explicit:true},{id:'melody',dimension:'melodicity',value:'melodic',explicit:true}];
const assessment={checks:conditions.map(c=>({conditionID:c.id,verdict:'match'})),relevance:.9,taste:1,reason:'Restrained delivery and mellow production'};
assert(accepts(conditions,assessment));
for(const verdict of ['conflict','uncertain'])assert(!accepts(conditions,{...assessment,checks:[{conditionID:'energy',verdict},{conditionID:'melody',verdict:'match'}]}));
assert(!accepts(conditions,{...assessment,checks:[{conditionID:'energy',verdict:'match'}]}));
assert(!accepts(conditions,{...assessment,relevance:NaN}));
for(const bad of [{history:[]},{liked:[]},{spotify:[]},{preferences:{source:'spotify'}},{preferences:{source:'user_explicit',history:[]}}])assert.throws(()=>validateV2({version:2,text:'chill melodic US hiphop',...bad}));
let calls=[];
globalThis.fetch=async(url,options)=>{
 const payload=JSON.parse(options.body);calls.push(payload);
 const stage=JSON.parse(payload.messages[0].content).stage;
 const content=stage==='parse_brief' ? {constraints:{conditions}} : stage==='retrieve' ? {constraints:{conditions},songs:[{artist:'Travis Scott',track:'SICKO MODE'},{artist:'Test Artist',track:'Mellow Fixture'}]} : {assessments:[{index:0,...assessment,checks:[{conditionID:'energy',verdict:'conflict'},{conditionID:'melody',verdict:'match'}]},{index:1,...assessment}]};
 return Response.json({stop_reason:'end_turn',content:[{type:'text',text:JSON.stringify(content)}]});
};
const result=await qualityBatch({version:2,text:'chill melodic US hiphop',preferences:{source:'user_explicit',artists:['Travis Scott']}},'dummy','test-model');
assert.equal(calls.length,3);
const generation=JSON.parse(calls[1].messages[0].content), review=JSON.parse(calls[2].messages[0].content);
assert.match(generation.calendar.today,/^\d{4}-\d{2}-\d{2}$/);
assert.deepEqual(generation.calendar,review.calendar);
assert.equal(result.rejectionCounts['energy:conflict'],1);assert.equal(result.songs.length,1);assert.equal(result.rejected,1);assert.equal(result.songs[0].track,'Mellow Fixture');
assert.match(result.songs[0].id,/^[a-f0-9]{64}$/);
console.log('PASS independent evaluation, explicit conflicts/uncertainty, malformed assessments, provenance allowlist, no artist bypass');
globalThis.fetch=async()=>Response.json({error:'limited'},{status:429,headers:{'retry-after':'120'}});
await assert.rejects(()=>qualityBatch({version:2,text:'chill hiphop'},'dummy','test-model'), e=>e.message==='busy'&&e.retryAfter===120);
console.log('PASS upstream Retry-After preserved');

// Personal fit is independent of brief fit; invented evidence must fail closed.
const candidates=[{artist:'New Artist',track:'Good'},{artist:'Unrelated Artist',track:'Random'},{artist:'Invented Link',track:'Random'}];
let captured=[];
globalThis.fetch=async(url,options)=>{
 const request=JSON.parse(options.body), payload=JSON.parse(request.messages[0].content);captured.push(payload);
 const content=payload.stage==='parse_brief' ? {constraints:{conditions}} : payload.songs ? {assessments:payload.songs.map(s=>({index:s.index,...assessment,taste:.8,
   tasteEvidence:s.artist==='New Artist' ? [{referenceID:'example:0',verdict:'match',detail:'Shared restrained melodic delivery'}] : s.artist==='Invented Link' ? [{referenceID:'spotify:0',verdict:'match',detail:'Not an allowed reference'}] : [],
   checks:conditions.map(c=>({conditionID:c.id,verdict:s.artist==='Seed'?'conflict':'match'}))
 }))} : {constraints:{conditions},songs:candidates};
 return Response.json({stop_reason:'end_turn',content:[{type:'text',text:JSON.stringify(content)}]});
};
const personalInput={version:2,text:'chill melodic hiphop',mode:'personal',preferences:{source:'user_explicit',examples:['Seed — Example']}};
const personal=await qualityBatch(personalInput,'dummy','fixture');
assert.deepEqual(personal.songs.map(x=>x.artist),['New Artist']);
assert.equal(personal.rejectionCounts['taste:unsupported'],2);
assert(captured.find(x=>x.songs)?.songs.some(x=>x.artist==='Seed')); // Injected example still rejected by brief gate.
const excluded=await qualityBatch({...personalInput,session:{source:'swipelist_model',excluded:[candidates[0]],feedback:[{...candidates[0],verdict:'keep'}]}},'dummy','fixture');
assert.equal(excluded.songs.length,0);
assert(captured.at(-1).feedback.some(x=>x.verdict==='keep'));
for(const session of [{source:'spotify',excluded:[]},{source:'swipelist_model',history:[]},{source:'swipelist_model',feedback:[{artist:'A',track:'B',verdict:'skip'}]},{source:'swipelist_model',excluded:[{artist:'A',track:'B',spotifyURI:'private'}]}])assert.throws(()=>validateV2({...personalInput,session}));
console.log('PASS personal evidence gate, unknown-artist musical connection, invalid references, seed admission, refill exclusion, feedback provenance');

assert(captured.filter(x=>x.stage==='parse_brief').every(x=>!('preferences' in x)&&!('references' in x)&&!('session' in x)));
console.log('PASS isolated brief parsing cannot ingest personal preferences');
