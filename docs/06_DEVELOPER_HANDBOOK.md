# Developer Handbook

## Run the App
```
flutter run -d windows
```

## Run Tests
```
flutter test
flutter test --reporter expanded
```

## Regenerate DI / Drift
```
dart run build_runner build --delete-conflicting-outputs
```

## Common Issues
- Missing DI annotations: ensure @injectable / @lazySingleton on new classes
- EOF syntax errors: never leave trailing EOF in files
- "Could not find a generator for route": use Navigator.push with MaterialPageRoute, not named routes
- Money must use int minor units (piasters), never double
EOF