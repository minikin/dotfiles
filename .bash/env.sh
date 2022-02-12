#!/bin/zsh

# Add commonly used folders to $PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Specify default editor. Possible values: vim, nano, ed etc.
export EDITOR=code

alias ..="cd .."

# quick edit aliases
alias reload="source ~/.zshrc"

# See disk usage in the current folder only
alias ds='du -h -d 1'

alias ll='ls -l'
alias cpwd='pwd | pbcopy' #copy working directory
alias cpdir=cpwd
alias brewu="brew upgrade && brew update"
alias pswrd="pwgen -Bncy 25"

# Git
alias gd='git diff'
alias g='git status'
alias gb='git branch'
alias grc='git rebase --continue'
alias gpp='git pull --rebase && git push'
alias gmff='git merge --ff-only'
alias gpull='git pull origin master'
alias gpush='git push origin master'
alias gc='git commit -v'
alias gca='git commit -v -a'
alias gl='git log --oneline'
alias gclean='git checkout -f &&  git clean -fd'
alias astudio='open -a /Applications/Android\ Studio.app'

# Pretty-printing
alias format_json='python -m json.tool'

# Start Simple Python Server
alias pserver='python -m SimpleHTTPServer 8000'

# Fetch remote repo and pull from branch
function gfpull() {
  git fetch && git pull origin $*
}

# Fetch remote repo and merge from branch
function gfmerge() {
  git fetch && git merge origin $*
}

# 
function gbranch() {
  git for-each-ref --count=30 --sort=-committerdate refs/heads/ --format='%(refname:short)'
}

# Create a new branch & switch to it
function gcb() {
  git checkout -b $*
}

# Move to a branch
function gco() {
  git checkout $*
}

# Commit pending changes and quote args
function gg() {
  git commit -v -a -m "$*"
}

# Fetch gitignore templates from gitignore.io
function gi() {
  curl https://www.gitignore.io/api/$*
}

function code {
    if [[ $# = 0 ]]
    then
        open -a "Visual Studio Code"
    else
        local argPath="$1"
        [[ $1 = /* ]] && argPath="$1" || argPath="$PWD/${1#./}"
        open -a "Visual Studio Code" "$argPath"
    fi
}

# Others
alias cppcompile='c++ -std=c++11 -stdlib=libc++'
alias zshconfig="code ~/.zshrc"
alias ohmyzsh="code ~/.oh-my-zsh"
alias oenv="code ~/env.sh"

# Flutter
alias fw='flutter packages pub run build_runner watch'
alias fwdelete='flutter packages pub run build_runner watch --delete-conflicting-outputs'
alias fri='flutter run --release'
alias fra='flutter build apk --release && flutter install'
alias frab='flutter build appbundle --target-platform android-arm,android-arm64 --release && flutter install'
alias ft='flutter test'
alias ftc='flutter test --coverage'
alias ftch='flutter test --coverage && genhtml coverage/lcov.info -o coverage/output/'

alias fvmw='fvm flutter packages pub run build_runner watch'
alias fvmd='fvm flutter packages pub run build_runner watch --delete-conflicting-outputs'

# Android Studio
alias astudio='open -a /Applications/Android\ Studio.app'

# Xcode
function xc() {
  project_file=$(cat <<EOF | ruby -rfileutils
  files = Dir.glob('**/*.{xcworkspace,xcodeproj}')
    .reject {|p|
      p.include?('Pods') ||
      p.include?('xcodeproj/project.xcworkspace') }
    .map {|x| [x, x.scan(/\//).count]}
    .sort {|a, b| a.last <=> b.last || a.first <=> b.first }
    .map {|x| x.first }
  puts files.first
EOF
)

  if [ -z "$project_file" ]
  then
    echo "Couldn't find a workspace or a project to open."
  else
    echo "Opening $project_file..."
    open "$project_file" -a /Applications/Xcode.app
  fi
}
