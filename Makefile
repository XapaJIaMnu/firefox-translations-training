#!make

.ONESHELL:
SHELL=/bin/bash

### 1. change these settings
SHARED_ROOT=/mnt/nanna0/nbogoych/data
CUDA_DIR=/usr/local/cuda
NUM_GPUS=8
# (optional) override available GPU ids, example GPUS=0 2 5 6
GPUS=
WORKSPACE=18000
CLUSTER_CORES=1
CONFIG=configs/config.fren.yml
CONDA_PATH=$(SHARED_ROOT)/mambaforge
SNAKEMAKE_OUTPUT_CACHE=$(SHARED_ROOT)/cache
# for CSD3 cluster
# MARIAN_CMAKE=-DBUILD_ARCH=core-avx2
MARIAN_CMAKE=
TARGET=
###

CONDA_ACTIVATE=source $(CONDA_PATH)/etc/profile.d/conda.sh ; conda activate ; conda activate
SNAKEMAKE=export SNAKEMAKE_OUTPUT_CACHE=$(SNAKEMAKE_OUTPUT_CACHE);  snakemake
CONFIG_OPTIONS=root="$(SHARED_ROOT)" cuda="$(CUDA_DIR)" workspace=$(WORKSPACE) numgpus=$(NUM_GPUS) $(if $(MARIAN_CMAKE),mariancmake="$(MARIAN_CMAKE)",) $(if $(GPUS),gpus="$(GPUS)",)

### 2. setup

git-modules:
	git submodule update --init --recursive

conda:
	wget https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-$$(uname)-$$(uname -m).sh
	bash Mambaforge-$$(uname)-$$(uname -m).sh -b -p $(CONDA_PATH)

snakemake:
	$(CONDA_ACTIVATE) base
	mamba create -c conda-forge -c bioconda -n snakemake snakemake==6.12.2 --yes
	mkdir -p "$(SNAKEMAKE_OUTPUT_CACHE)"

# build container image for cluster and run-local modes (preferred)
build:
	sudo singularity build Singularity.sif Singularity.def

# or pull container image from a registry if there is no sudo
pull:
	singularity pull Singularity.sif library://evgenypavlov/default/bergamot2:latest


### 3. run

# if you need to activate conda environment for direct snakemake commands, use
# . $(CONDA_PATH)/etc/profile.d/conda.sh && conda activate snakemake

dry-run:
	$(CONDA_ACTIVATE) snakemake
	$(SNAKEMAKE) \
	  --use-conda \
	  --cores all \
	  --cache \
	  --reason \
	  --configfile $(CONFIG) \
	  --config $(CONFIG_OPTIONS) deps=true  \
	  -n \
	  $(TARGET)

test-dry-run: CONFIG=configs/config.test.yml
test-dry-run: dry-run

run-local:
	echo "Running with config $(CONFIG)"
	$(CONDA_ACTIVATE) snakemake
	$(SNAKEMAKE) \
	  --use-conda \
	  --resources gpu=$(NUM_GPUS) \
	  --configfile $(CONFIG) \
	  --config $(CONFIG_OPTIONS) \
	  --cores 1 \
	  --cache \
	  --reason \
	  $(TARGET)

test: CONFIG=configs/config.test.yml
test: run-local

run-local-container:
	$(CONDA_ACTIVATE) snakemake
	module load singularity
	$(SNAKEMAKE) \
	  --use-conda \
	  --use-singularity \
	  --reason \
	  --cores all \
	  --cache \
	  --resources gpu=$(NUM_GPUS) \
	  --configfile $(CONFIG) \
	  --config $(CONFIG_OPTIONS) \
	  --singularity-args="--bind $(SHARED_ROOT),$(CUDA_DIR) --nv" \
	  $(TARGET)

run-slurm:
	$(CONDA_ACTIVATE) snakemake
	chmod +x profiles/slurm/*
	$(SNAKEMAKE) \
	  --use-conda \
	  --reason \
	  --cores $(CLUSTER_CORES) \
	  --cache \
	  --configfile $(CONFIG) \
	  --config $(CONFIG_OPTIONS) \
	  --profile=profiles/slurm \
	  $(TARGET)

run-slurm-container:
	$(CONDA_ACTIVATE) snakemake
	chmod +x profiles/slurm/*
	module load singularity
	$(SNAKEMAKE) \
	  --use-conda \
	  --use-singularity \
	  --reason \
	  --verbose \
	  --cores $(CLUSTER_CORES) \
	  --cache \
	  --configfile $(CONFIG) \
	  --config $(CONFIG_OPTIONS) \
	  --profile=profiles/slurm \
	  --singularity-args="--bind $(SHARED_ROOT),$(CUDA_DIR),/tmp --nv --containall" \
	  $(TARGET)
# if CPU nodes don't have access to cuda dirs, use
# export CUDA_DIR=$(CUDA_DIR); $(SNAKEMAKE) \
# --singularity-args="--bind $(SHARED_ROOT),/tmp --nv --containall"


### 4. create a report

report:
	$(CONDA_ACTIVATE) snakemake
	REPORTS=$(SHARED_ROOT)/reports DT=$$(date '+%Y-%m-%d_%H-%M'); \
	mkdir -p $$REPORTS && \
	snakemake \
		--report $${REPORTS}/$${DT}_report.html \
		--configfile $(CONFIG) \
		--config $(CONFIG_OPTIONS)

run-file-server:
	$(CONDA_ACTIVATE) snakemake
	python -m  http.server --directory $(SHARED_ROOT)/reports 8000

### extra

dag: CONFIG=configs/config.test.yml
dag:
	snakemake \
	  --dag \
	  --configfile $(CONFIG) \
	  --config $(CONFIG_OPTIONS) \
	  | dot -Tpdf > DAG.pdf

install-tensorboard:
	$(CONDA_ACTIVATE) base
	conda env create -f envs/tensorboard.yml

tensorboard:
	$(CONDA_ACTIVATE) tensorboard
	ls -d $(SHARED_ROOT)/models/*/*/* > tb-monitored-jobs; \
	tensorboard --logdir=$$MODELS --host=0.0.0.0 &; \
	python utils/tb_log_parser.py --prefix=
