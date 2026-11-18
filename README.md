# App Locker

An Android-first Flutter app that lets you choose installed apps to protect with a PIN.

## Setup

1. Open App Locker and create a 4-8 digit PIN.
2. Select the apps you want to lock.
3. Enable App Locker under Android Accessibility settings.

The PIN is stored as a salted PBKDF2 hash. The accessibility service observes
app/window changes only to detect when a selected app opens; it does not retrieve
screen content. Android may stop the
service in battery-saving modes, and some device manufacturers may require
allowing background activity for reliable operation. Users can turn the service
off at any time in Android settings.

## Platform note

App enforcement is implemented for Android. iOS does not provide general
third-party apps with permission to block arbitrary apps; Apple's Screen Time
and Family Controls APIs have separate entitlement and use-case requirements.
