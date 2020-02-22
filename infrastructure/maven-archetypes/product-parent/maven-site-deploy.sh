#!/bin/sh
mvn -Dsite.deployment.personal.main=file:///tmp clean site-deploy
