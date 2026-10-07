.PHONY: all clean

all:
	@echo "Building Windows-AGI-Mesh..."
	# Add your build commands here
	# Examples:
	# dotnet build
	# cargo build --release
	# g++ -o bin/mesh src/*.cpp

clean:
	rm -rf build/
	rm -rf bin/
