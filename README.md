# Cosmo
> WARNING: Cosmo is deprecated as I don't use it anymore. I switched to some bash+janet scripts that live directly in my dotfiles repo.

If you want to this yourself initialize the repo like described in https://www.atlassian.com/git/tutorials/dotfiles
and build your own small bash script to manage it. To keep machine local changes I use a unique branch per client/node type and continously rebase it on the main branch.

## Old Description
Cosmo is a simple git-based dotfile management tool, with some added features that I found useful.  
*Warning*: Cosmo is by far not ready to be used by anyone else most certainly not for production, many features are inconsistent or not implemented at all. It will receive multiple overhauls of it's model, especially for the cryptography and the implementation of sigchains. I'm also still evaluating the optimal internal data structure.

## Goals
- Managment of dotfiles with optionally encrypted files
- Node managment with groups using a siggraph (a sigchain that can fork and merge)
- ssh key managment of nodes (they sign a statment using their node-key which ssh pubkey belongs to them)
- secrets that are only accessible by groups specified
- general key-value store with support for glob patterns for listing
- ssh hosts managment
- event system to send message in a pub-sub fashion to groups
- No real backend needed, just someway to synchronize the git repo (in practice this will be nearly always a central git server)