// Synthetic data only. Run from the repo root after installing bridge dependencies.
import http from 'node:http';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../bridge/package.json',import.meta.url));
const {WebSocketServer}=require('ws');
const sessions=new Map([['fixture-chat',{sessionId:'fixture-chat',updatedAt:Date.now(),cwd:'/workspace/demo',running:false,projections:{values:{title:'一次简单的远程协作',modelSelection:{next:{model:'deepseek-flash'}}}}}]]);
const archived=new Set(); let seq=10; const sockets=new Set();
const event=(type,data,n=seq++)=>({type,seq:n,data});
const records=[
 event('user/message',{content:[{type:'text',text:'帮我看下今天的项目进度。'}]},1),
 event('tool/call',{callId:'fixture-command',name:'bash',arguments:{description:'查看工作区状态',command:'git status --short'}},2),
 event('tool/result',{message:{source:{callId:'fixture-command'},content:[{type:'text',text:'工作区整洁，检查完成。'}]}},3),
 event('assistant/message',{message:{content:[{type:'text',text:'## 进度已经整理好了\n\n手机和电脑共用同一份会话，接着上次的思路就好。\n\n| 模块 | 状态 | 说明 | 下一步 |\n| --- | --- | --- | --- |\n| 客户端 | 已完成 | 支持深色模式与工作区 | 测试安装包 |\n| 桥接 | 已连接 | 电脑端保持运行 | 查看二维码 |\n\n你可以继续发消息，也可以切换工作区。'}]}},4)
];
const workspace=()=>({items:[{workspaceId:'fixture-workspace',title:'示例工作区',path:'/workspace/demo',sessionIds:[...sessions.keys()]}],archivedSessionIds:[...archived]});
const server=http.createServer(async(req,res)=>{
 if(req.headers.authorization!=='Bearer '+'a'.repeat(64)){res.writeHead(403).end();return;}
 let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>32*1024*1024){res.writeHead(413).end();return;}}
 let body;try{body=JSON.parse(raw);}catch{res.writeHead(400).end();return;}
 const args=body.payload?.args??{},r=args.request??{};let value={};
 switch(body.method){
  case 'session/list':value={items:[...sessions.values()]};break;
  case 'session/create':sessions.set(r.sessionId,{sessionId:r.sessionId,updatedAt:Date.now(),cwd:'/workspace/demo',projections:{values:{title:'Android 新对话'}}});value={sessionId:r.sessionId};break;
  case 'workspace/archiveSession':archived.add(r.sessionId);value={archivedSessionIds:[...archived]};break;
  case 'workspace/unarchiveSession':archived.delete(r.sessionId);value={archivedSessionIds:[...archived]};break;
  case 'session/modelCatalog':value={groups:[{id:'deepseek',name:'DeepSeek',models:[{id:'deepseek-flash',name:'DeepSeek Flash',reasoning:{efforts:[{id:'high',name:'High'}]}}]}]};break;
  case 'permissionPresets/catalog':value={options:[{value:'workspace-write',name:'工作区写入'},{value:'read-only',name:'只读'}]};break;
  case 'commands/list':value=[{name:'compact',description:'压缩当前会话的上下文'},{name:'permission',description:'查看或设置会话权限',input:{hint:'权限预设'}}];break;
  case 'commands/execute':value={result:{kind:'success'}};break;
  case 'session/selectModel':value={};break;
  case 'session/page':value={records:[event('user/message',{content:[{type:'text',text:'这是更早的一条消息。'}]},0)],hasMore:false};break;
  case 'session/prompt':{
   value={accepted:true};
   for(const ws of sockets)if(ws.sessionId===r.sessionId){
    send(ws,{type:'event',event:event('user/message',{content:r.content})});
    send(ws,{type:'event',event:event('turn/start',{})});
    send(ws,{type:'assistant-stream',frame:{type:'start',revision:1,attemptId:'fixture-attempt'}});
    setTimeout(()=>send(ws,{type:'assistant-stream',frame:{type:'chunk',revision:2,attemptId:'fixture-attempt',index:0,chunk:{type:'text-delta',text:'已经收到，我们继续。'}}}),100);
    setTimeout(()=>{send(ws,{type:'event',event:event('assistant/message',{message:{content:[{type:'text',text:'已经收到，我们继续。'}]}})});send(ws,{type:'event',event:event('turn/end',{})});send(ws,{type:'waterfall',event:'approval/request',eventId:'fixture-approval-'+seq,agentId:r.sessionId,request:{toolName:'读取示例文件',reason:'这是虚构数据的审批测试。'}});},400);
   }
   break;
  }
  case '$events/result':value={};console.log('PASS: approval/question response received');break;
  case 'session/cancel':for(const ws of sockets)send(ws,{type:'event',event:event('turn/end',{})});break;
  default:res.writeHead(404).end();return;
 }
 res.setHeader('content-type','application/json');res.end(JSON.stringify({result:{ok:true,value}}));
});
const wss=new WebSocketServer({noServer:true});
server.on('upgrade',(req,socket,head)=>{if(req.headers.authorization!=='Bearer '+'a'.repeat(64)){socket.end('HTTP/1.1 403 Forbidden\r\n\r\n');return;}wss.handleUpgrade(req,socket,head,ws=>wss.emit('connection',ws));});
function send(ws,value){if(ws.readyState===1)ws.send(JSON.stringify({type:'next',streamId:'follow',value}));}
wss.on('connection',ws=>{sockets.add(ws);ws.on('close',()=>sockets.delete(ws));ws.on('message',data=>{const msg=JSON.parse(data);if(msg.endpoint==='$events')send(ws,{type:'ready',clientId:'fixture-client'});if(msg.endpoint==='workspace/follow')send(ws,{type:'baseline',value:workspace()});if(msg.endpoint==='session/follow'){ws.sessionId=msg.payload.args.request.address.sessionId;send(ws,{type:'snapshot',cursor:9,records,hasMore:true,projections:{values:{modelSelection:{next:{model:'deepseek-flash'}}}},assistantStream:{revision:0}});}});});
server.listen(38081,'127.0.0.1',()=>console.log('Synthetic Android fixture listening on loopback port 38081.'));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{for(const ws of sockets)ws.terminate();server.closeAllConnections();server.close();});
