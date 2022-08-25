ARG BASE_IMAGE
FROM $BASE_IMAGE

RUN apk update && apk add alpine-sdk less
RUN gem install bundler

ADD . /app/src
WORKDIR /app/src

RUN bundle install
