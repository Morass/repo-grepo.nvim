# Makefile for repo-grepo.nvim C++ search backend

CXX ?= g++
CXXFLAGS = -std=c++17 -O3 -Wall -Wextra
TARGET = bin/repo-grepo-search
SRC = src/search.cpp

# Detect OS for cross-platform compilation
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    CXXFLAGS += -pthread
endif
ifeq ($(UNAME_S),Darwin)
    # macOS specific flags if needed
endif

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SRC)
	@echo "Build complete: $(TARGET)"

clean:
	rm -f $(TARGET)
	@echo "Clean complete"

test: $(TARGET)
	@echo "Testing file search..."
	./$(TARGET) files . "test" "" ""
	@echo "Test complete"

.PHONY: all clean test
