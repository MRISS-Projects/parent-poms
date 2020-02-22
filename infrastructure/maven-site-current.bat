@echo off
call mvn -N -Dsite.deployment.personal.main=file:///tmp clean site
