.PHONY=up
up:
	bash script.sh up

.PHONY=setup
setup:
	bash script.sh setup

.PHONY=build
build:
	bash script.sh build

.PHONY=dependencies
dependencies:
	bash script.sh dependencies