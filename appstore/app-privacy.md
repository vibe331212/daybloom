# Daybloom: App Privacy answers (App Store Connect → App Privacy)

These match `privacy.html` on the website and `ios/Daybloom/PrivacyInfo.xcprivacy` in the app.
If the app ever starts collecting something new, update all three together.

## Step 1: "Do you or your third-party partners collect data from this app?"
**Yes, we collect data from this app.**

## Step 2: Pick these data types (and nothing else)

| Section in Apple's list | Data type | Why Daybloom has it |
|---|---|---|
| Contact Info | **Name** | The display name friends see (not a real or legal name) |
| Identifiers | **User ID** | The username |
| User Content | **Emails or Text Messages** | Chat messages |
| User Content | **Photos or Videos** | Photos sent in chats and group photos |
| User Content | **Customer Support** | Messages sent through Contact support, and reports |
| User Content | **Other User Content** | Calendar events, friends list, reactions, group names |

Do **not** pick: Email Address, Phone Number, Physical Address, Location, Contacts, Health, Financial Info, Browsing or Search History, Purchases, Usage Data, Diagnostics, Device ID, or Advertising Data. Daybloom doesn't collect any of these.

## Step 3: For **each** data type above, answer the same way

| Question | Answer |
|---|---|
| How is it used? | **App Functionality** only |
| Is it linked to the user's identity? | **Yes** |
| Is it used for tracking? | **No** |

## Result Apple will show on your App Store page
- **Data Used to Track You:** none
- **Data Linked to You:** Contact Info, Identifiers, User Content
- **Data Not Linked to You:** none
