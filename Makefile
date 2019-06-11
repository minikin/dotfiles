JAVA := $(shell command -v java  2> /dev/null)
BREW := $(shell command -v brew 2> /dev/null)

setup:
ifndef JAVA
	$(error "Please install java before running `make setup`: https://www.oracle.com/technetwork/java/javase/downloads/jdk12-downloads-5295953.html")
endif
ifndef BREW
	$(error "Please install brew before running `make setup`: https://brew.sh/")
endif
	@echo "--------------------------------";
	@echo "0: Updateing brew."
	@echo "--------------------------------";
	brew upgrade
	@echo "--------------------------------";
	@echo "1: Installing git."
	@echo "--------------------------------";
	brew install git
	@echo "--------------------------------";
	@echo "2: Installing caskroom."
	@echo "--------------------------------";
	brew tap caskroom/cask
	@echo "--------------------------------";
	@echo "3: Installing Apps."
	@echo "--------------------------------";
	brew cask install \
	alfred \
	android-file-transfer \
	appcleaner \
	docker \
	transmission \
	vlc \
	fastlane \
	# visual-studio-code \
	# iterm2
	@echo "--------------------------------";
	@echo "4: Installing Oh My Zsh."
	@echo "--------------------------------";
	# curl -Lo install.sh https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh
	# sh install.sh
	# rm -f install.sh
	@echo "--------------------------------";
	@echo "6: Installing CocoaPods."
	@echo "--------------------------------";
	sudo gem install cocoapods
	@echo "";
	@echo "";
	@echo "--------------------------------";
	@echo "Successfully completed a new mac set-up!"
	@echo "--------------------------------";

  
