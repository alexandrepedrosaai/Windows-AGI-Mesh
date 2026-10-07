.PHONY: all clean

all:
	@echo "Building Windows-AGI-Mesh..."
	mkdir -p bin
	cp Windows-AGI-Mesh.qs bin/
	# Add your build commands here
	# Examples:
	# dotnet build
	# cargo build --release
	# g++ -o bin/mesh src/*.cpp

clean:
	rm -rf build/
	rm -rf bin/
