COFFEE=node_modules/.bin/coffee

build:
	$(COFFEE) -co lib src

clean:
	rm -rf lib
