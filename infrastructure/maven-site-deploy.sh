#!/bin/sh
mvn -nsu -npu -Dsite.deployment.personal.main=file:///tmp clean site-deploy
