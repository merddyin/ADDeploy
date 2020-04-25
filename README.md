# ADDeploy
Used to deploy components to support an ESAE forest and RBAC model via native control. Of course, this simple statement barely scratches the surface of my hopes for what this PowerShell module will be able to do eventually. The overall goal of this project is to build a tool that can completely deploy and maintain all aspects of an ESAE forest infrastructure; the base configuration, OU structures, delegation models, and tons of other goodies. I know...it sounds (IS) daunting, but this won't be my first attempt, and I've got a lot of lessons learned, and even some code I hope to reutilize to make the process smoother. First, a little background...

# History
## Version 1
The first version was built almost by accident. I was on a project where I had to deploy a LOT of OUs, groups, and ACLs (over 20k OUs alone). There was no way I was doing that by hand of course, so I used PowerShell, and was smart enough to keep the snippets. It turned out that maintaining everything after the initial deployment was going to overwhelm the support team without help, so version 1 came to be. It was very specific to the needs of that particular effort, but had some limited customizeability. It was reused at a few different efforts with minor enhancements, but it had some bugs and I knew it could be better.

## Version 2
Very little of the code ended up being reused for the next version in the end...nearly total rewrite. This version used a SQLite DB to hold preferences and the core of the customization engine as well. The new version made HUGE strides in customizeability...verious levels of organizational structure, anywhere from 1 to perhaps 5 or 6, depending on naming, though this is more about AD limits and the mechanisms used for creating the RBAC groups. Another challenge that was overcome was one of size and speed, which was overcome with memory management techniques and runspaces. While deployment functionality was good to go, it was still missing some things...like management functionality...and a setup utility. Should those be finished...probably, but once again I found limitations in my design I didn't like. 

# Future
So, here we are with today, and building the next version. This one won't quite be a full rewrite though...I think there's lot's of solid code in V2, I just had some shortcomings in the architecture that need fixing sooner than later. For example, the module doesn't currently deal with deploying the actual 'Red' forest, just the 'Gold'. It also doesn't account for...ya know...multiple 'Gold' forests. The biggest challenge is the data structure and storage...there isn't enough extensibility and, perhaps the larger of the data source issues...decentralized configuration storage might cause some useability issues. So, I'm setting out to fix it...one step at a time. 
