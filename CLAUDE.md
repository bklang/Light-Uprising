# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sparkle Friend is a multi-platform SwiftUI application that supports iOS (26.1+), macOS (15.7+), and visionOS (26.1+). The app uses SwiftData for persistent data storage with a simple list-based interface for managing timestamped items.

## Build and Test Commands

### Building the Application
```bash
# Build for all platforms
xcodebuild -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -configuration Debug build

# Build for specific platform
xcodebuild -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -destination 'platform=macOS' build
xcodebuild -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Running Tests
```bash
# Run all tests
xcodebuild test -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -destination 'platform=macOS'

# Run specific test target
xcodebuild test -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -destination 'platform=macOS' -only-testing:Sparkle_FriendTests

# Run UI tests
xcodebuild test -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -destination 'platform=macOS' -only-testing:Sparkle_FriendUITests

# Run a single test
xcodebuild test -project "Sparkle Friend.xcodeproj" -scheme "Sparkle Friend" -destination 'platform=macOS' -only-testing:Sparkle_FriendTests/Sparkle_FriendTests/testExample
```

## Architecture

### Data Layer
- **SwiftData** is the persistence framework
- `Item` model (`Item.swift`) is a `@Model` class with SwiftData that stores timestamped entries
- `ModelContainer` is configured in `Sparkle_FriendApp.swift` with schema registration
- Data is persisted to disk (not in-memory) by default

### Application Structure
- **Sparkle_FriendApp.swift**: Main app entry point with `@main` attribute. Creates and manages the shared `ModelContainer` that provides SwiftData persistence across the app
- **ContentView.swift**: Primary view using `NavigationSplitView` with master-detail layout. Uses `@Query` to reactively fetch items from SwiftData and `@Environment(\.modelContext)` to perform CRUD operations
- **Item.swift**: SwiftData model representing a timestamped entry

### Platform-Specific UI
The app uses conditional compilation for platform-specific UI:
- `#if os(macOS)` blocks adjust navigation split view column width on macOS
- `#if os(iOS)` blocks add iOS-specific toolbar items like EditButton
- Supports iPhone, iPad, Mac, and Apple Vision Pro

### Key Patterns
- SwiftData models use the `@Model` macro
- Views access data through `@Query` property wrapper for reactive updates
- Model operations use `modelContext.insert()` and `modelContext.delete()`
- Animations wrap data mutations with `withAnimation {}`
- The `.modelContainer()` modifier injects the model container into the view hierarchy

## Project Configuration
- **Bundle ID**: net.dashblue.Sparkle-Friend
- **Swift Version**: 5.0
- **Deployment Targets**: iOS 26.1, macOS 15.7, visionOS 26.1
- **Code Signing**: Automatic
- **Sandboxing**: App Sandbox enabled with readonly file access
