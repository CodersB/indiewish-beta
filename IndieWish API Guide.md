# Super Simple API - IndieWish iOS SDK

## 🎯 Just 2 Steps!

### Step 1: Configure (One Line!)

```swift
import IndieWish

// In AppDelegate or App init:
IndieWish.configure(
    secret: "your-key",
    email: "user@example.com",
    subscription: .paid,
    billingCycle: .monthly,
    amount: "$9.99"
)
```

### Step 2: Send Feedback (One Line!)

```swift
// When user wants to send feedback:
try await IndieWish.sendFeedback(
    title: "Add dark mode",
    category: "feature"
)
```

**That's it!** ✨ Everything else is automatic!

---

## 📱 Real Examples

### Example 1: Free User (Anonymous)

```swift
// No email, no subscription info needed!
IndieWish.configure(secret: "your-key")
```

### Example 2: Free User with Email

```swift
IndieWish.configure(
    secret: "your-key",
    email: "user@example.com"
)
```

### Example 3: Paid User (Monthly $9.99)

```swift
IndieWish.configure(
    secret: "your-key",
    email: "user@example.com",
    subscription: .paid,
    billingCycle: .monthly,
    amount: "$9.99"
)
```

### Example 4: Premium User (Yearly $99)

```swift
IndieWish.configure(
    secret: "your-key",
    email: "premium@example.com",
    subscription: .premium,
    billingCycle: .yearly,
    amount: "$99.99"
)
```

### Example 5: Trial User

```swift
IndieWish.configure(
    secret: "your-key",
    email: "trial@example.com",
    subscription: .trial
)
```

---

## 🔄 When Things Change

### User Upgrades to Paid

```swift
IndieWish.updateUser(
    email: "user@example.com",
    subscription: .paid,
    billingCycle: .monthly,
    amount: "$9.99"
)
```

### User Email Changes

```swift
IndieWish.updateUser(
    email: "newemail@example.com",
    subscription: .paid
)
```

### User Cancels Subscription

```swift
IndieWish.updateUser(
    email: "user@example.com",
    subscription: .free
)
```

### User Signs Out

```swift
IndieWish.updateUser(subscription: .free)
// Email automatically cleared
```

---

## 📖 Complete App Example

```swift
import UIKit
import IndieWish
import FirebaseAuth

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure IndieWish - ONE LINE!
        setupIndieWish()
        
        // Listen for auth changes
        listenToAuthChanges()
        
        return true
    }
    
    private func setupIndieWish() {
        // Get current user
        let currentUser = Auth.auth().currentUser
        
        // Configure based on user state
        if let email = currentUser?.email {
            // User is signed in
            IndieWish.configure(
                secret: "your-ingest-secret",
                email: email,
                subscription: isPaidUser() ? .paid : .free,
                billingCycle: .monthly,
                amount: "$9.99"
            )
        } else {
            // Anonymous user
            IndieWish.configure(secret: "your-ingest-secret")
        }
    }
    
    private func listenToAuthChanges() {
        Auth.auth().addStateDidChangeListener { auth, user in
            if let email = user?.email {
                // User signed in - update
                IndieWish.updateUser(
                    email: email,
                    subscription: self.isPaidUser() ? .paid : .free
                )
            } else {
                // User signed out - clear
                IndieWish.updateUser(subscription: .free)
            }
        }
    }
    
    private func isPaidUser() -> Bool {
        // Your subscription check logic
        return false
    }
}
```

---

## 💰 Subscription Types

```swift
SubscriptionTier:
- .unknown    // Default, not configured
- .free       // Free tier user
- .trial      // Trial period user
- .paid       // Paying subscriber
- .premium    // Premium/highest tier

BillingCycle:
- .monthly    // $X/month
- .yearly     // $X/year
- .weekly     // $X/week
- .lifetime   // One-time purchase
```

---

## 🎨 UI Integration

### SwiftUI

```swift
struct SettingsView: View {
    @State private var showFeedback = false
    
    var body: some View {
        Button("Send Feedback") {
            showFeedback = true
        }
        .sheet(isPresented: $showFeedback) {
            IndieWishFeedbackFormView()
        }
    }
}
```

### UIKit

```swift
class ViewController: UIViewController {
    
    @IBAction func sendFeedbackTapped() {
        Task {
            try await IndieWish.sendFeedback(
                title: "Feature request",
                description: "Add widgets",
                category: "feature"
            )
        }
    }
}
```

---

## 🔍 What Shows in Dashboard

After configuration, your dashboard shows:

```
User Profile:
├─ Email: user@example.com
├─ Subscription: paid
├─ Billing: monthly ($9.99)
├─ Device: iPhone 15 Pro
└─ All their feedback
```

---

## ⚡ Quick Comparison

### Old Way (Complex) ❌
```swift
// Too many steps!
let profile = UserProfile(
    subscriptionStatus: "paid",
    subscriptionExpiresAt: someDate,
    email: "user@email.com",
    customMetadata: ["billing": "monthly"]
)
IndieWish.configure(secret: "key", userProfile: profile)
```

### New Way (Simple) ✅
```swift
// One line!
IndieWish.configure(
    secret: "key",
    email: "user@email.com",
    subscription: .paid,
    billingCycle: .monthly,
    amount: "$9.99"
)
```

---

## 🚀 Migration Guide

If you're using the old API, just simplify it:

### Before:
```swift
let profile = UserProfile(
    subscriptionStatus: "paid",
    email: "user@email.com"
)
IndieWish.configure(secret: "key", userProfile: profile)
```

### After:
```swift
IndieWish.configure(
    secret: "key",
    email: "user@email.com",
    subscription: .paid
)
```

**Both work!** The old API is still available as `configureAdvanced()`.

---

## 📝 Common Patterns

### Pattern 1: Configure on Launch
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {
    IndieWish.configure(
        secret: "key",
        email: currentUserEmail(),
        subscription: currentSubscriptionTier()
    )
    return true
}
```

### Pattern 2: Update on Purchase
```swift
func handlePurchase(plan: String, amount: String) {
    IndieWish.updateUser(
        email: currentUserEmail(),
        subscription: .paid,
        billingCycle: .monthly,
        amount: amount
    )
}
```

### Pattern 3: Update on Sign In/Out
```swift
func userDidSignIn(email: String) {
    IndieWish.updateUser(
        email: email,
        subscription: .free
    )
}

func userDidSignOut() {
    IndieWish.updateUser(subscription: .free)
}
```

---

## 💡 Pro Tips

1. **Call configure() once** - In AppDelegate/App init
2. **Call updateUser()** - When subscription or email changes
3. **sendFeedback()** - Anytime, anywhere!
4. **All optional** - Only pass what you have

---

## ❓ FAQ

**Q: Do I need to pass all parameters?**  
A: No! Everything except `secret` is optional.

**Q: What if I don't have email?**  
A: Skip it! Just: `IndieWish.configure(secret: "key")`

**Q: What if subscription changes?**  
A: Call `updateUser(subscription: .paid)`

**Q: Is the old API still available?**  
A: Yes! Use `configureAdvanced()` for complex cases.

---

## 🎉 Summary

**Before:** 5+ lines, complex UserProfile objects  
**After:** 1 line, type-safe enums, autocomplete  

```swift
// Literally this simple:
IndieWish.configure(
    secret: "key",
    email: "user@email.com",
    subscription: .paid,
    billingCycle: .monthly,
    amount: "$9.99"
)
```

**Your developers will thank you!** 🙏


