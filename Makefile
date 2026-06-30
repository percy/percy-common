# setup default base image
BASE_IMAGE ?= ruby:3.3-alpine@sha256:940f1f8ba78c93b303eb2a632b249792cf60435517da260f3a1b9c8b8f1e7dfe

build:
	docker-compose build --build-arg BASE_IMAGE="$(BASE_IMAGE)"

lint: build
	docker-compose run app sh -c 'bundle exec rubocop'

test: build
	docker-compose run app sh -c 'bundle exec rspec'
