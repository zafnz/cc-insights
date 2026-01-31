#!/bin/bash

cd backend-node && npm run bundle   # Creates bundled backend
cd frontend && flutter build macos  # Backend automatically included
