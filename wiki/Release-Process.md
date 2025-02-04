# Last Update October 2, 2024 

# Release Process Overview
- Create a new branch in the repo's
- Update `openshift/release` with the new branch
- Create a new commit to the repo updating any locations which refer to the image version to the new version (add one if it doesn't exist)
- Cherry Pick the commit to the new branch (with the correct CI this will then add the new tag to quay)
- Update the ObO image versions in main.go
- Update the plugin components in COO konflux