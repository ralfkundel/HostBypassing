# Location of the CUDA Toolkit
CUDA_PATH ?= /usr/local/cuda-11.2
# HOST_ARCH   := $(shell uname -m)
# TARGET_ARCH ?= $(HOST_ARCH)
# HOST_OS   := $(shell uname -s 2>/dev/null | tr "[:upper:]" "[:lower:]")
# TARGET_OS ?= $(HOST_OS)
HOST_COMPILER ?= g++
NVCC          := $(CUDA_PATH)/bin/nvcc -ccbin $(HOST_COMPILER)
NVCCFLAGS   := -m64
ifeq ($(dbg),1)
      NVCCFLAGS += -g -G
      BUILD_TYPE := debug
else
      BUILD_TYPE := release
endif
ALL_CCFLAGS :=
ALL_CCFLAGS += $(NVCCFLAGS)
ALL_CCFLAGS += --threads 0
SAMPLE_ENABLED := 1
ALL_LDFLAGS :=
ALL_LDFLAGS += $(ALL_CCFLAGS)

INCLUDES  := -I ""
LIBRARIES := -lcuda
SMS ?= 52 60 61 70 75 80 86
ifeq ($(GENCODE_FLAGS),)
# Generate SASS code for each SM architecture listed in $(SMS)
$(foreach sm,$(SMS),$(eval GENCODE_FLAGS += -gencode arch=compute_$(sm),code=sm_$(sm)))

# Generate PTX code from the highest SM architecture in $(SMS) to guarantee forward-compatibility
HIGHEST_SM := $(lastword $(sort $(SMS)))
ifneq ($(HIGHEST_SM),)
GENCODE_FLAGS += -gencode arch=compute_$(HIGHEST_SM),code=compute_$(HIGHEST_SM)
endif
endif

EXEC :=

all: build

build: main

check.deps:
ifeq ($(SAMPLE_ENABLED),0)
	@echo "Sample will be waived due to the above missing dependencies"
else
	@echo "Sample is ready - all dependencies have been met"
endif

main.o:main.cu ../settings.h
	$(EXEC) $(NVCC) $(INCLUDES) $(ALL_CCFLAGS) $(GENCODE_FLAGS) -o $@ -c $<

main: main.o
	$(EXEC) $(NVCC) $(ALL_LDFLAGS) $(GENCODE_FLAGS) -o $@ $+ $(LIBRARIES)
#	$(EXEC) mkdir -p ../../bin/$(TARGET_ARCH)/$(TARGET_OS)/$(BUILD_TYPE)
#	$(EXEC) cp $@ ../../bin/$(TARGET_ARCH)/$(TARGET_OS)/$(BUILD_TYPE)

run: build
	$(EXEC) ./main

clean:
	rm -f main main.o
#	rm -rf ../../bin/$(TARGET_ARCH)/$(TARGET_OS)/$(BUILD_TYPE)/main

clobber: clean
