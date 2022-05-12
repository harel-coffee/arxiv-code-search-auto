.PHONY: clean data lint requirements sync_data_to_s3 sync_data_from_s3

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BUCKET = [OPTIONAL] your-bucket-for-syncing-data (do not include 's3://')
PROFILE = default
PROJECT_NAME = feat-store
PYTHON_INTERPRETER = python3

ifeq (,$(shell which conda))
HAS_CONDA=False
else
HAS_CONDA=True
endif

#################################################################################
# COMMANDS                                                                      #
#################################################################################

environment:
ifeq (True,$(HAS_CONDA)) # assume on local
	@echo ">>> Detected conda. Assume local computer. Installing packages from yml."
	bash install_conda_local.sh
else # assume on HPC
	@echo ">>> No Conda detected. Assume on HPC."
	bash install_env_hpc.sh
	@echo ">>> venv created. Activate with source ~/arxiv/bin/activate"
endif


## Download data
download:
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/data/download_arxiv_kaggle.py
else # assume on HPC
	$(PYTHON_INTERPRETER) src/data/download_arxiv_kaggle.py
endif

## Parse entire metadata json to csv
## 
parse_json:
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/data/parse_json.py
else # assume on HPC
	sbatch src/data/parse_json_hpc.sh
endif

## Select subset of papers based on criteria
## and save to a new CSV file that will be used as a definitive index
paper_index:
ifeq (True,$(HAS_CONDA)) # assume on local
	bash src/data/make_paper_index_local.sh
else # assume on HPC
	sbatch src/data/parse_json.sh
endif


## Download papers from arxiv
download_papers:
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/data/download_papers.py --index_file_no 2
else # assume on HPC
	$(PYTHON_INTERPRETER) src/data/download_papers.py --index_file_no 3
endif


## Make Dataset
txt: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/data/make_txt.py --n_cores 6 --pdf_root_dir $(PROJECT_DIR)/data/raw/pdfs/ --index_file_no 7
else # assume on HPC
	sbatch src/data/make_txt_hpc.sh
endif

## Perform search of keywords in papers
search: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/data/search_txt.py --index_file_no 2 --overwrite --keep_old_files --max_token_len 350
else # assume on HPC
	sbatch src/data/search_txt_hpc.sh
endif

## Compile the labels from all the individual search csvs
labels: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/data/make_labels.py --path_data_folder $(PROJECT_DIR)/data/ --n_cores 2 --file_type ods
else # assume on HPC
	sbatch src/data/search_txt_hpc.sh
endif

## Copy labels from project_dir to scratch (only on HPC)
copy_labels: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	echo "On local compute."
else # assume on HPC
	bash src/data/copy_labels_to_scratch.sh
endif


download_pretrained_bert: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) $(PROJECT_DIR)/src/models/download_pretrained_bert.py
else # assume on HPC
	$(PYTHON_INTERPRETER) $(PROJECT_DIR)/src/models/download_pretrained_bert.py
endif

## Train
train: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) $(PROJECT_DIR)/src/models/train_model.py
else # assume on HPC
	sbatch src/models/train_model_hpc.sh $(PROJECT_DIR)
endif


## Train
train_dummy: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) $(PROJECT_DIR)/src/models/train_model.py
else # assume on HPC
	sbatch src/models/train_model_hpc_dummy.sh $(PROJECT_DIR)
endif


## Make Features
features: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/features/build_features.py --path_data_folder $(PROJECT_DIR)/data/
else # assume on HPC
	bash src/features/scripts/chain_build_feat_and_combine.sh $(PROJECT_DIR)
endif


## Select Features, Scale, and return Data Splits
splits: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/features/select_feat_and_scale.py --path_data_folder $(PROJECT_DIR)/data/
else # assume on HPC
	sbatch src/features/scripts/split_and_save_hpc.sh $(PROJECT_DIR)
endif

train: requirements
ifeq (True,$(HAS_CONDA)) # assume on local
	$(PYTHON_INTERPRETER) src/models/train.py
else # assume on HPC
	sbatch src/features/scripts/split_and_save_hpc.sh $(PROJECT_DIR)
endif

## Delete all compiled Python files
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete
	find . -type f -name "*.out" -delete


## Run unit and integration tests
test:
	$(PYTHON_INTERPRETER) -m unittest discover -s tests

#################################################################################
# PROJECT RULES                                                                 #
#################################################################################



#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
