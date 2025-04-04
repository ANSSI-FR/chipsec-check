# Add a new third-party repository

```
cd third-party/
# Add -b <branch> if you want to track a specific branch instead of HEAD
git submodule add https://github.com/chipsec/chipsec.git
```

# Update all repositories to their latest version

```
git submodule update --recursive --remote
git diff --submodule
git add third-party/*
git commit -m "Update all third-party repositories"
```

# Update a repository to a specific version

Example with chispec:

```
cd third-party/chipsec
git checkout 1.13.0
cd ..
git add chispec
git commit -m "Update chipsec to v1.13.0"
```

# Clean-up the content of submodules

```
sudo git submodule foreach git clean -fdx
```

