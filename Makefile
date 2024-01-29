# setup default base image
BASE_IMAGE ?= ruby:3.0.0-alpine

build:
	docker-compose build --build-arg BASE_IMAGE="$(BASE_IMAGE)"

lint: build
	docker-compose run app sh -c 'bundle exec rubocop'

test: build
	docker-compose run app sh -c 'bundle exec rspec'
