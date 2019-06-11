setup:
	@echo "--------------------------------";
	@echo "1: Installing brew"
	@echo "--------------------------------";
	/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  @echo "--------------------------------";
	@echo "2: Installing git"
	@echo "--------------------------------";
  brew install git
  @echo "--------------------------------";
	@echo "3: Installing caskroom"
	@echo "--------------------------------";
  brew tap caskroom/cask
  @echo "--------------------------------";
	@echo "4: Installing Apps"
	@echo "--------------------------------";
  brew cask install \
    alfred \
    android-file-transfer \
    appcleaner \
    docker \
    totalfinder \
    transmission \
    vlc \
    visual-studio-code \
    iterm2
  @echo "--------------------------------";
	@echo "5: Installing Oh My Zsh"
	@echo "--------------------------------";
  $ sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

  
