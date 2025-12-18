#!/bin/bash

set -ex

mkdir out/EMASCAResource
cp cacert.pem out/EMASCAResource/cacert.pem
mv out/EMASCAResource out/EMASCAResource.bundle