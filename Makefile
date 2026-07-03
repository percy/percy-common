# setup default base image (digest-pinned so the default build cannot be
# silently swapped via a mutable tag)
BASE_IMAGE ?= ruby:2.6-alpine@sha256:382ce92de42ef027bf1bfe382c3f3c3878042c41c07da8b8aa41855db0894762

build:
	docker-compose build --build-arg BASE_IMAGE="$(BASE_IMAGE)"

lint: build
	docker-compose run app sh -c 'bundle exec rubocop'

test: build
	docker-compose run app sh -c 'bundle exec rspec'
