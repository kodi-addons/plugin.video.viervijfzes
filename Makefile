export KODI_HOME := $(CURDIR)/tests/home
export KODI_INTERACTIVE := 0
PYTHON := python

# Collect information to build as sensible package name
name = $(shell xmllint --xpath 'string(/addon/@id)' addon.xml)
version = $(shell xmllint --xpath 'string(/addon/@version)' addon.xml)
ifdef release
	zip_name = $(name)-$(version).zip
else
	git_branch = $(shell git rev-parse --abbrev-ref HEAD)
	git_hash = $(shell git rev-parse --short HEAD)
	zip_name = $(name)-$(version)-$(git_branch)-$(git_hash).zip
endif

all: check test build
zip: build
multizip: build-all

check: check-pylint check-translations

check-pylint:
	@printf ">>> Running pylint checks\n"
	@$(PYTHON) -m pylint *.py resources/lib/ tests/

check-translations:
	@printf ">>> Running translation checks\n"
	@$(foreach lang,$(filter-out en_gb, $(patsubst resources/language/resource.language.%, %, $(wildcard resources/language/*))), \
		msgcmp resources/language/resource.language.$(lang)/strings.po resources/language/resource.language.en_gb/strings.po; \
	)
	@tests/check_for_unused_translations.py

check-addon: check-addon-matrix

check-addon-leia:
	@printf ">>> Running addon checks\n"
	@make -s build-leia && cd dist/ && kodi-addon-checker --branch=leia

check-addon-matrix:
	@printf ">>> Running addon checks\n"
	@make -s build-matrix && cd dist/ && kodi-addon-checker --branch=matrix

codefix:
	@isort -l 160 resources/

test: test-unit

test-unit:
	@printf ">>> Running unit tests\n"
	@$(PYTHON) -m pytest tests

clean:
	@printf ">>> Cleaning up\n"
	@find . -name '*.py[cod]' -type f -delete
	@find . -name '__pycache__' -type d -delete
	@rm -rf .pytest_cache/ tests/cdm tests/userdata/temp
	@rm -f *.log .coverage
	@rm -rf dist/

build: build-matrix

build-all: build-leia build-matrix

build-leia: clean
	$(eval abi=2.26.0)
	@rm -rf dist/ && mkdir dist/
	@git archive --format tar --worktree-attributes --prefix $(name)/ $(or $(shell git stash create), HEAD) | (cd dist/ && tar -xf -)
	@sed -i -E "s/(<!--)?(\s*<import addon=\"xbmc\.python\" version=\")[0-9\.]*(\"\/>)(\s*-->)?/\2$(abi)\3/" dist/$(name)/addon.xml
	@cd dist && zip --quiet -9 -r ../../$(zip_name) $(name)
	@printf ">>> Successfully wrote package for Kodi 18 as ../$(zip_name)\n"

build-matrix: clean
	$(eval abi=3.0.0)
	$(eval version=$(version)+matrix.1)
	@rm -rf dist/ && mkdir dist/
	@git archive --format tar --worktree-attributes --prefix $(name)/ $(or $(shell git stash create), HEAD) | (cd dist/ && tar -xf -)
	@sed -i -E "s/(<!--)?(\s*<import addon=\"xbmc\.python\" version=\")[0-9\.]*(\"\/>)(\s*-->)?/\2$(abi)\3/" dist/$(name)/addon.xml
	@printf "cd /addon/@version\nset $(version)\nsave\nbye\n" | xmllint --shell dist/$(name)/addon.xml > /dev/null
	@cd dist && zip --quiet -9 -r ../../$(zip_name) $(name)
	@printf ">>> Successfully wrote package for Kodi 19 as ../$(zip_name)\n"

# You first need to run sudo gem install github_changelog_generator for this
release:
ifneq ($(release),)
	@github_changelog_generator -u add-ons -p $(name) --no-issues --exclude-labels duplicate,question,invalid,wontfix release --future-release v$(release);

	@printf "cd /addon/@version\nset $$release\nsave\nbye\n" | xmllint --shell addon.xml; \
	date=$(shell date '+%Y-%m-%d'); \
	printf "cd /addon/extension[@point='xbmc.addon.metadata']/news\nset v$$release ($$date)\nsave\nbye\n" | xmllint --shell addon.xml; \

	# Next steps to release:
	# - Modify the news-section of addons.xml
	# - git add . && git commit -m "Prepare for v$(release)" && git push
	# - git tag v$(release) && git push --tags
else
	@printf "Usage: make release release=1.0.0\n"
endif
