@echo off
call mvn -Dsite.deployment.personal.main=file:///tmp clean site
