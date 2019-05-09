alias ..="cd .."

# quick edit aliases
alias reload="source ~/.bash/aliases.bash"

# See disk usage in the current folder only
alias ds='du -h -d 1'

alias ll='ls -l'
alias cpwd='pwd | pbcopy' #copy working directory
alias cpdir=cpwd

#terminal
function title() {
  echo -n -e "\033]0;$1\007"
}

#Finder
alias o='open . &'

#Processes
alias tu='top -o cpu' # processes sorted by CPU
alias tm='top -o vsize' # processes sorted by Memory

#Rails
alias rs='bundle exec rails server'
alias r='rake'
alias rmig='bundle exec rake db:migrate'
alias rc='bundle exec rails console'

# CocoaPods
alias pod-dev=$HOME/projects/CocoaPods/bin/pod

# bundler
alias bec='bundle exec cucumber'
function be() {
  bundle exec $*
}

#Heroku
function hrmig() {
  heroku rake db:migrate --app $1
}

function hrdeploy {
  rake heroku:deploy app=$1
}

# Chef
alias kc='knife cookbook'
alias kcu='knife cookbook upload'

#Git
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

# Pretty-printing
alias format_json='python -m json.tool'

#fetch remote repo and pull from branch
function gfpull() {
  git fetch && git pull origin $*
}

#create a new branch & switch to it
function gcb() {
  git checkout -b $*
}

#move to a branch
function gco() {
  git checkout $*
}

#commit pending changes and quote args
function gg() {
  git commit -v -a -m "$*"
}

# fetch gitignore templates from gitignore.io
function gi() {
  curl https://www.gitignore.io/api/$*
}

alias gd='git diff'

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

# starts an HTTP server on port 8000
alias pserve='python -m SimpleHTTPServer 8000'

tab-color() {
    echo -ne "\033]6;1;bg;red;brightness;$1\a"
    echo -ne "\033]6;1;bg;green;brightness;$2\a"
    echo -ne "\033]6;1;bg;blue;brightness;$3\a"
}

tab-reset() {
    echo -ne "\033]6;1;bg;*;default\a"
}


#Flutter
alias fw='flutter packages pub run build_runner watch'
alias fwdelete='flutter packages pub run build_runner watch --delete-conflicting-outputs'
alias fri='flutter run --release'
alias fra='flutter build apk --release && flutter install'
alias ft='flutter test'
alias ftc='flutter test --coverage'
alias ftch='flutter test --coverage && genhtml coverage/lcov.info -o coverage/output/'

