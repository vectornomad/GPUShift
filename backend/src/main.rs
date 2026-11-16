//! GPUShift v0.1: provider-neutral SSH GPU workload router.
//! No third party crates. Does not pretend remote GPUs are native Metal devices.
use std::{env, fs, io, path::PathBuf, process::{Command, Stdio}};

#[derive(Clone, Debug)]
struct Profile { id:String, vendor:String, label:String, host:String, port:u16, user:String, identity:String, stream_host:String }

fn valid_token(s:&str) -> bool { !s.is_empty() && s.len() <= 255 && s.chars().all(|c|c.is_ascii_alphanumeric() || "-._:@".contains(c)) }
fn valid_path(s:&str) -> bool { !s.is_empty() && !s.contains('\n') && !s.contains('\r') && !s.contains('\0') }
fn quote(s:&str)->String { format!("'{}'", s.replace('\'', "'\\''")) }
fn config_path()->PathBuf {
    if let Ok(v)=env::var("GPUSHIFT_PROFILES") { return PathBuf::from(v); }
    let home=env::var("HOME").unwrap_or_else(|_|".".into());
    PathBuf::from(home).join(".config/gpushift/profiles.tsv")
}
fn load()->Result<Vec<Profile>,String> {
    let path=config_path();
    let data=fs::read_to_string(&path).map_err(|e|format!("Cannot read {}: {e}",path.display()))?;
    let mut profiles=Vec::new();
    for (i,line) in data.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {continue}
        let x:Vec<&str>=line.split('\t').collect();
        if x.len()!=8 {return Err(format!("Line {}: expected eight TAB-separated fields",i+1))}
        let port=x[4].parse::<u16>().map_err(|_|format!("Line {}: invalid port",i+1))?;
        if port==0 || !valid_token(x[0]) || !valid_token(x[1]) || !valid_token(x[3]) || !valid_token(x[5]) || !valid_path(x[6]) || (!x[7].is_empty() && !valid_token(x[7])) {
            return Err(format!("Line {}: invalid profile field",i+1))
        }
        if !["NVIDIA","AMD","Intel"].contains(&x[1]) { return Err(format!("Line {}: vendor must be NVIDIA, AMD or Intel",i+1)); }
        profiles.push(Profile{id:x[0].into(),vendor:x[1].into(),label:x[2].into(),host:x[3].into(),port,user:x[5].into(),identity:x[6].into(),stream_host:x[7].into()});
    }
    if profiles.is_empty() {return Err("No profiles configured".into())}
    Ok(profiles)
}
fn selected<'a>(p:&'a [Profile],id:&str)->Result<&'a Profile,String> {p.iter().find(|x|x.id==id).ok_or_else(||format!("Unknown profile: {id}"))}
fn ssh_args(p:&Profile)->Vec<String> {
    let mut a=vec!["-o".into(),"BatchMode=yes".into(),"-o".into(),"ConnectTimeout=10".into(),"-o".into(),"StrictHostKeyChecking=yes".into(),"-p".into(),p.port.to_string()];
    if !p.identity.is_empty() && p.identity!="-" {a.push("-i".into());a.push(p.identity.clone());}
    a.push(format!("{}@{}",p.user,p.host)); a
}
fn ssh(p:&Profile, remote:&str)->Result<(),String> {
    let mut args=ssh_args(p); args.push(remote.into());
    let status=Command::new("ssh").args(&args).status().map_err(|e|format!("ssh: {e}"))?;
    if status.success(){Ok(())}else{Err(format!("SSH exited with {status}"))}
}
fn scp(p:&Profile,src:&str,dst:&str,download:bool)->Result<(),String> {
    let mut args=vec!["-o".into(),"BatchMode=yes".into(),"-o".into(),"StrictHostKeyChecking=yes".into(),"-P".into(),p.port.to_string()];
    if p.identity!="-" && !p.identity.is_empty(){args.push("-i".into());args.push(p.identity.clone());}
    // scp's remote syntax requires care: user-controlled remote paths are intentionally not accepted.
    let remote=format!("{}@{}:{}",p.user,p.host,if download{"/tmp/gpushift/output/"}else{"/tmp/gpushift/input.blend"});
    if download { args.push("-r".into());args.push(remote);args.push(dst.into()); }
    else {args.push(src.into());args.push(remote);}
    let status=Command::new("scp").args(args).status().map_err(|e|format!("scp: {e}"))?;
    if status.success(){Ok(())}else{Err(format!("SCP exited with {status}"))}
}
fn probe(p:&Profile)->Result<(),String>{
    let cmd=match p.vendor.as_str(){
        "NVIDIA"=>"nvidia-smi --query-gpu=name,memory.total,utilization.gpu --format=csv,noheader",
        "AMD"=>"(rocm-smi --showproductname --showmeminfo vram || rocminfo | head -35)",
        _=>"(xpu-smi discovery || sycl-ls || lspci | grep -i -E 'intel.*(graphics|gaudi)')"
    };
    ssh(p,cmd)
}
fn ai(p:&Profile)->Result<(),String>{
    let cmd="python3 -c 'import torch; print(\"PyTorch:\",torch.__version__); print(\"CUDA/ROCm available:\",torch.cuda.is_available()); print(\"Devices:\", torch.cuda.device_count()); print(\"Device name:\",torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"No PyTorch GPU found\")'";
    ssh(p,cmd)
}
fn render(p:&Profile,file:&str,frame:u32,out:&str)->Result<(),String>{
    if !file.ends_with(".blend") || !std::path::Path::new(file).is_file(){return Err("Provide an existing .blend file".into())}
    fs::create_dir_all(out).map_err(|e|e.to_string())?;
    ssh(p,"mkdir -p /tmp/gpushift/output && rm -f /tmp/gpushift/output/frame_*")?;
    scp(p,file,"",false)?;
    let remote=format!("blender -b /tmp/gpushift/input.blend -o /tmp/gpushift/output/frame_##### -f {frame}");
    ssh(p,&remote)?;
    scp(p,"",out,true)?;
    println!("Render transferred to {out}"); Ok(())
}
fn stream(p:&Profile)->Result<(),String>{
    if p.stream_host.is_empty() || p.stream_host=="-" {return Err("No stream_host configured for this profile".into())}
    // Moonlight's host pairing and Sunshine host setup must be completed separately.
    println!("Opening Moonlight. Pair/select host {} in the Moonlight UI.",p.stream_host);
    let status=Command::new("open").args(["-a","Moonlight"]).status().map_err(|e|format!("Cannot launch Moonlight: {e}"))?;
    if status.success(){Ok(())}else{Err(format!("Moonlight launch failed: {status}"))}
}
fn usage(){eprintln!("GPUShift CLI\n  gpushift list\n  gpushift probe <id>\n  gpushift ai <id>\n  gpushift render <id> <file.blend> <frame> <output-directory>\n  gpushift stream <id>\n  gpushift doctor\nProfiles: $GPUSHIFT_PROFILES or ~/.config/gpushift/profiles.tsv");}
fn run()->Result<(),String>{
    let a:Vec<String>=env::args().collect(); if a.len()<2 {usage();return Err("Missing command".into())}
    if a[1]=="doctor" {println!("GPUShift CLI: OK\nProfiles: {}\nssh installed: {}\nscp installed: {}",config_path().display(),Command::new("ssh").arg("-V").stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok(),Command::new("scp").arg("-h").stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok());return Ok(())}
    let profiles=load()?;
    if a[1]=="list" {for p in &profiles {println!("{}\t{}\t{}\t{}",p.id,p.vendor,p.label,p.host)} return Ok(())}
    if a.len()<3{usage();return Err("Missing profile ID".into())}
    let p=selected(&profiles,&a[2])?;
    match a[1].as_str(){
      "probe"=>probe(p), "ai"=>ai(p), "stream"=>stream(p),
      "render"=>{if a.len()!=6 {usage();return Err("render needs a file, frame, and output directory".into())}
          let frame=a[4].parse::<u32>().map_err(|_|"Invalid frame number".to_string())?;
          render(p,&a[3],frame,&a[5])},
      _=>{usage();Err(format!("Unknown command: {}",a[1]))}
    }
}
fn main(){if let Err(e)=run(){eprintln!("GPUShift error: {e}");std::process::exit(1)}}
