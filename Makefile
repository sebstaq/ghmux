test:
	./test/test-ghmux.sh

lint:
	bash -n bin/ghmux lib/ghmux.sh test/test-ghmux.sh
