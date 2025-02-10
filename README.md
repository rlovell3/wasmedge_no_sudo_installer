# wasmedge_no_sudo_installer  
A modified wasmedge installer that doesn't need sudo and is made for me, a longtime user of oh-my-zsh on Linux, with enough customizations over the years to never want anyone ever, ever touching anything on my machine.  

Here's the quick and dirty:  
The original wasmedge installation script is incredible.  It's one of the more interesting shell scripts I've ever read.  
However, I wanted to modify a few things for my own personal installation.  

My reason for making these modifications is that I already have a BOSS oh-my-zsh configuration with CUDA libs, Nvidia GPU totally tricked out, massive time invested in configuring every imaginable development tool and library, and years of tightly-configured everything. I never, ever want somebody's generic installation script to make assumptions about what I have installed, what environment variables I may already have set, and I absolutely don't want to run such a script from out there in the wild with sudo privilege.  

So, ... here is a summary of the modifications I've made to the amazing original script:  
1.  download to a static dir: ~/Downloads/wasm  (which I create before the script runs just because that is how I roll).  
2.  save the downloaded files after finishing rather than deleting them.
3.  perform the install in ~/.wasmedge directory
4.  Don't modify .zshrc.  Instead print all shell modifications to a new file: ~/.oh-my-zsh/custom/wasmedge.zsh (so I can easily keep up with them).
5.  Verbose priint every single step to stdout and also to a log file in ~/.wasmedge
6.  Completely remove the need to have sudo privilege to run the script.  

So, look: I have no idea if this highly modified script will run on systems other than the machines I personally own. I don't know if it will work on Windoes or Macs, or even if it will run on any of the 6 Arch Linux boxes I have surrounding me. What I built this script for was to get it going on my Pop OS development box (this is NOT a recommendation for PoP OS. Those System76 guys fucked me over like you would not believe.  They even never read the Gigabyte Motherboard manual, which clearly states not to insert an NVMe drive in the slot nearest the CPU if you happen to be running a GPU in the same-mapped PCie slot.  Just by reading the manual and moving the drive, I generated an 8x speed-up of my GPU.  Thanks for nothing System 76 assholes).

If you dare run this script, I insist that you feed it into a Chat AI model first, and ask it to explicitly tell you every single detail of what the script is doing to your machine (and your life) before you run it.  The original came with an Apache License, and thus, I've attached an Apache License hereto.  But really, don't run this script unless you are a heavily experienced Linux user who knows how to compile C++, Rust, work with conda/miniconda, compile Boost libs, etc., and values a tight, clean system that only you make edits to.  
