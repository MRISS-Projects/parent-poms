@echo off
call mvn -nsu -npu -Dsite.deployment.personal.main=file:///tmp clean site-deploy
