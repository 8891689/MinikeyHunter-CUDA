# =================================================================================
# Makefile for MinikeyCuda
#
# How to use:
#   - Release build (GPU): make gpu=1
#   - Debug build (GPU):   make gpu=1 debug=1
#   - Clean up:            make clean
# =================================================================================

TARGET = minikey
CXX = g++
CC = gcc
CUDA ?= /usr/local/cuda
CXXCUDA ?= /usr/bin/g++
NVCC = $(CUDA)/bin/nvcc
OBJDIR = obj

CXX_SOURCES = lib/hash/ripemd160.cpp lib/hash/ripemd160_sse.cpp lib/hash/sha256.cpp lib/hash/sha256_sse.cpp lib/util.cpp lib/Int.cpp lib/Point.cpp lib/SECP256K1.cpp lib/IntGroup.cpp lib/IntMod.cpp lib/V/VBase58.cpp
C_SOURCES = lib/base58.c
CU_SOURCES = lib/hash/sha256.cu Worker.cu main.cu

CXX_OBJS = $(patsubst lib/hash/sha256.cpp,$(OBJDIR)/hash/sha256cpp.o,$(patsubst %.cpp,$(OBJDIR)/%.o,$(CXX_SOURCES)))
C_OBJS   = $(patsubst %.c,$(OBJDIR)/%.o,$(C_SOURCES))
CU_OBJS  = $(patsubst %.cu,$(OBJDIR)/%.o,$(CU_SOURCES))

INCLUDES = -I. -I$(CUDA)/include
CXX_COMMON_FLAGS = -std=c++11 -m64 -msse4.2 -Wno-unused-result -Wno-write-strings
C_COMMON_FLAGS = -m64

ifdef gpu
    OBJS = $(CXX_OBJS) $(C_OBJS) $(CU_OBJS)
    LFLAGS = -lpthread -L$(CUDA)/lib64 -lcudart
    ifdef debug
        CXXFLAGS = -g $(CXX_COMMON_FLAGS) $(INCLUDES)
        CFLAGS = -g $(C_COMMON_FLAGS)
        NVCC_OPT_FLAGS = -G
    else
        CXXFLAGS = -O3 $(CXX_COMMON_FLAGS) $(INCLUDES)
        CFLAGS = -O3 $(C_COMMON_FLAGS)
        NVCC_OPT_FLAGS = -O3
    endif
else
    OBJS = $(CXX_OBJS) $(C_OBJS)
    LFLAGS = -lpthread
    ifdef debug
        CXXFLAGS = -g $(CXX_COMMON_FLAGS)
        CFLAGS = -g $(C_COMMON_FLAGS)
    else
        CXXFLAGS = -O3 $(CXX_COMMON_FLAGS)
        CFLAGS = -O3 $(C_COMMON_FLAGS)
    endif
endif


NVCC_ARCH_FLAGS = -gencode=arch=compute_61,code=sm_61 -gencode=arch=compute_75,code=sm_75 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90

all: $(TARGET)

$(TARGET): $(OBJS)
	@echo "Linking executable: $@"
	$(CXX) $^ $(LFLAGS) -o $@

$(OBJDIR)/%.o : %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -o $@ -c $<

$(OBJDIR)/hash/sha256cpp.o: lib/hash/sha256.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -o $@ -c $<

$(OBJDIR)/%.o : %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ -c $<

ifdef gpu
$(OBJDIR)/%.o: %.cu
	@mkdir -p $(dir $@)
	$(NVCC) $(NVCC_OPT_FLAGS) --ptxas-options=-v -maxrregcount=0 --compile --compiler-options -fPIC -ccbin $(CXXCUDA) -m64 $(INCLUDES) $(NVCC_ARCH_FLAGS) -o $@ -c $<
endif

clean:
	@echo "Cleaning..."
	@rm -rf $(OBJDIR) $(TARGET)

.PHONY: all clean
