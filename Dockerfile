ARG BASE_IMAGE
FROM $BASE_IMAGE

RUN apk update && apk add alpine-sdk
RUN gem install bundler -v 2.4.22

ADD . /app/src
WORKDIR /app/src

RUN bundle install
