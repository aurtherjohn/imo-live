import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Fast. Private. Yours.'**
  String get appTagline;

  /// No description provided for @tabChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get tabChats;

  /// No description provided for @tabUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get tabUpdates;

  /// No description provided for @tabCommunities.
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get tabCommunities;

  /// No description provided for @tabCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get tabCalls;

  /// No description provided for @tabContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get tabContacts;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchOrAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask Imo LIVE or Search'**
  String get searchOrAsk;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchHint;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @star.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get star;

  /// No description provided for @unstar.
  ///
  /// In en, this message translates to:
  /// **'Unstar'**
  String get unstar;

  /// No description provided for @react.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get react;

  /// No description provided for @translate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @unarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchive;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// No description provided for @markAsUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get markAsUnread;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @chatInfo.
  ///
  /// In en, this message translates to:
  /// **'Chat info'**
  String get chatInfo;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @readAll.
  ///
  /// In en, this message translates to:
  /// **'Read all'**
  String get readAll;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get filterUnread;

  /// No description provided for @filterFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get filterFavorites;

  /// No description provided for @filterGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get filterGroups;

  /// No description provided for @filterWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get filterWork;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @noChatsMessage.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation and it will show up here.'**
  String get noChatsMessage;

  /// No description provided for @noRecentCalls.
  ///
  /// In en, this message translates to:
  /// **'No recent calls'**
  String get noRecentCalls;

  /// No description provided for @noRecentCallsMessage.
  ///
  /// In en, this message translates to:
  /// **'Calls you make and receive will appear here.'**
  String get noRecentCallsMessage;

  /// No description provided for @noStarredMessages.
  ///
  /// In en, this message translates to:
  /// **'No starred messages'**
  String get noStarredMessages;

  /// No description provided for @noStarredMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap and hold a message to star it for later.'**
  String get noStarredMessage;

  /// No description provided for @noArchivedChats.
  ///
  /// In en, this message translates to:
  /// **'No archived chats'**
  String get noArchivedChats;

  /// No description provided for @noArchivedMessage.
  ///
  /// In en, this message translates to:
  /// **'Chats you archive are kept here.'**
  String get noArchivedMessage;

  /// No description provided for @noBlockedContacts.
  ///
  /// In en, this message translates to:
  /// **'No blocked contacts'**
  String get noBlockedContacts;

  /// No description provided for @noBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Contacts you block will appear here.'**
  String get noBlockedMessage;

  /// No description provided for @noChannels.
  ///
  /// In en, this message translates to:
  /// **'Follow channels to see updates'**
  String get noChannels;

  /// No description provided for @noChannelsMessage.
  ///
  /// In en, this message translates to:
  /// **'Channels let you follow updates from people and organisations.'**
  String get noChannelsMessage;

  /// No description provided for @noUpdates.
  ///
  /// In en, this message translates to:
  /// **'No updates yet'**
  String get noUpdates;

  /// No description provided for @noUpdatesMessage.
  ///
  /// In en, this message translates to:
  /// **'Status updates from your contacts appear here for 24 hours.'**
  String get noUpdatesMessage;

  /// No description provided for @stayConnected.
  ///
  /// In en, this message translates to:
  /// **'Stay connected with a community'**
  String get stayConnected;

  /// No description provided for @stayConnectedMessage.
  ///
  /// In en, this message translates to:
  /// **'Communities bring members together in topic-based groups, and let you send announcement groups easily.'**
  String get stayConnectedMessage;

  /// No description provided for @startYourCommunity.
  ///
  /// In en, this message translates to:
  /// **'Start your community'**
  String get startYourCommunity;

  /// No description provided for @seeExampleCommunities.
  ///
  /// In en, this message translates to:
  /// **'See example communities'**
  String get seeExampleCommunities;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get messageDeleted;

  /// No description provided for @edited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get edited;

  /// No description provided for @forwarded.
  ///
  /// In en, this message translates to:
  /// **'Forwarded'**
  String get forwarded;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'typing...'**
  String get typing;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get offline;

  /// No description provided for @lastSeenRecently.
  ///
  /// In en, this message translates to:
  /// **'last seen recently'**
  String get lastSeenRecently;

  /// No description provided for @typeAMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get typeAMessage;

  /// No description provided for @noInternetConnection.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get noInternetConnection;

  /// No description provided for @backOnline.
  ///
  /// In en, this message translates to:
  /// **'Back online'**
  String get backOnline;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @newContact.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get newContact;

  /// No description provided for @newCommunity.
  ///
  /// In en, this message translates to:
  /// **'New community'**
  String get newCommunity;

  /// No description provided for @newChannel.
  ///
  /// In en, this message translates to:
  /// **'New channel'**
  String get newChannel;

  /// No description provided for @broadcastLists.
  ///
  /// In en, this message translates to:
  /// **'Broadcast lists'**
  String get broadcastLists;

  /// No description provided for @linkedDevices.
  ///
  /// In en, this message translates to:
  /// **'Linked devices'**
  String get linkedDevices;

  /// No description provided for @starredMessages.
  ///
  /// In en, this message translates to:
  /// **'Starred messages'**
  String get starredMessages;

  /// No description provided for @archivedChats.
  ///
  /// In en, this message translates to:
  /// **'Archived chats'**
  String get archivedChats;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @earnPoints.
  ///
  /// In en, this message translates to:
  /// **'Earn points'**
  String get earnPoints;

  /// No description provided for @unreadChats.
  ///
  /// In en, this message translates to:
  /// **'Unread chats'**
  String get unreadChats;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @lists.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get lists;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @storageAndData.
  ///
  /// In en, this message translates to:
  /// **'Storage and data'**
  String get storageAndData;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper'**
  String get wallpaper;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLock;

  /// No description provided for @twoStepVerification.
  ///
  /// In en, this message translates to:
  /// **'Two-step verification'**
  String get twoStepVerification;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @blockedContacts.
  ///
  /// In en, this message translates to:
  /// **'Blocked contacts'**
  String get blockedContacts;

  /// No description provided for @disappearingMessages.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get disappearingMessages;

  /// No description provided for @securityNotifications.
  ///
  /// In en, this message translates to:
  /// **'Security notifications'**
  String get securityNotifications;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @keypad.
  ///
  /// In en, this message translates to:
  /// **'Keypad'**
  String get keypad;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @endCall.
  ///
  /// In en, this message translates to:
  /// **'End call'**
  String get endCall;

  /// No description provided for @muteAction.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get muteAction;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetooth;

  /// No description provided for @addPerson.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get addPerson;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get switchCamera;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get document;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @poll.
  ///
  /// In en, this message translates to:
  /// **'Poll'**
  String get poll;

  /// No description provided for @event.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get event;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @selectCountry.
  ///
  /// In en, this message translates to:
  /// **'Select country'**
  String get selectCountry;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @aboutField.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutField;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupDescription.
  ///
  /// In en, this message translates to:
  /// **'Group description'**
  String get groupDescription;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @admins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get admins;

  /// No description provided for @exitGroup.
  ///
  /// In en, this message translates to:
  /// **'Exit group'**
  String get exitGroup;

  /// No description provided for @inviteLink.
  ///
  /// In en, this message translates to:
  /// **'Invite link'**
  String get inviteLink;

  /// No description provided for @myStatus.
  ///
  /// In en, this message translates to:
  /// **'My status'**
  String get myStatus;

  /// No description provided for @recentUpdates.
  ///
  /// In en, this message translates to:
  /// **'Recent updates'**
  String get recentUpdates;

  /// No description provided for @viewedUpdates.
  ///
  /// In en, this message translates to:
  /// **'Viewed updates'**
  String get viewedUpdates;

  /// No description provided for @mutedUpdates.
  ///
  /// In en, this message translates to:
  /// **'Muted updates'**
  String get mutedUpdates;

  /// No description provided for @addStatus.
  ///
  /// In en, this message translates to:
  /// **'Add status'**
  String get addStatus;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @messageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent'**
  String get messageSent;

  /// No description provided for @permissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get permissionNeeded;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @comingWithBackend.
  ///
  /// In en, this message translates to:
  /// **'This will be available in a later version.'**
  String get comingWithBackend;

  /// No description provided for @somethingWentWrongOnThis.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on this screen'**
  String get somethingWentWrongOnThis;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @myLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get myLocation;

  /// No description provided for @approximateLocation.
  ///
  /// In en, this message translates to:
  /// **'Approximate location'**
  String get approximateLocation;

  /// No description provided for @signInToStartEarning.
  ///
  /// In en, this message translates to:
  /// **'Sign in to start earning'**
  String get signInToStartEarning;

  /// No description provided for @couldNotAddPointsCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not add points — check your connection'**
  String get couldNotAddPointsCheck;

  /// No description provided for @signInFirst.
  ///
  /// In en, this message translates to:
  /// **'Sign in first'**
  String get signInFirst;

  /// No description provided for @premiumActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Premium active until '**
  String get premiumActiveUntil;

  /// No description provided for @couldNotActivatePremiumCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not activate premium — check your connection'**
  String get couldNotActivatePremiumCheck;

  /// No description provided for @thisContactHasNoAccount.
  ///
  /// In en, this message translates to:
  /// **'This contact has no account to receive a gift'**
  String get thisContactHasNoAccount;

  /// No description provided for @couldNotSendTheGift.
  ///
  /// In en, this message translates to:
  /// **'Could not send the gift — check your connection'**
  String get couldNotSendTheGift;

  /// No description provided for @ad.
  ///
  /// In en, this message translates to:
  /// **'Ad'**
  String get ad;

  /// No description provided for @takeAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takeAPhoto;

  /// No description provided for @opensTheDeviceCamera.
  ///
  /// In en, this message translates to:
  /// **'Opens the device camera'**
  String get opensTheDeviceCamera;

  /// No description provided for @thisWindowIsInsideImo.
  ///
  /// In en, this message translates to:
  /// **'This window is inside Imo LIVE'**
  String get thisWindowIsInsideImo;

  /// No description provided for @secureSignIn.
  ///
  /// In en, this message translates to:
  /// **'Secure sign-in'**
  String get secureSignIn;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// No description provided for @facebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get facebook;

  /// No description provided for @orContinueWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Or continue with email'**
  String get orContinueWithEmail;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPassword;

  /// No description provided for @sendLink.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get sendLink;

  /// No description provided for @verifyYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyYourEmail;

  /// No description provided for @openTheLinkInThe.
  ///
  /// In en, this message translates to:
  /// **'Open the link in the email to confirm this address. '**
  String get openTheLinkInThe;

  /// No description provided for @resendNow.
  ///
  /// In en, this message translates to:
  /// **'Resend now'**
  String get resendNow;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @setUpYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Set up your profile'**
  String get setUpYourProfile;

  /// No description provided for @thisIsHowOtherPeople.
  ///
  /// In en, this message translates to:
  /// **'This is how other people find you on Imo LIVE.'**
  String get thisIsHowOtherPeople;

  /// No description provided for @addAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get addAPhoto;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @joinImoLIVEInA.
  ///
  /// In en, this message translates to:
  /// **'Join Imo LIVE in a few seconds.'**
  String get joinImoLIVEInA;

  /// No description provided for @orSignUpWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Or sign up with email'**
  String get orSignUpWithEmail;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @clearCallLog.
  ///
  /// In en, this message translates to:
  /// **'Clear call log'**
  String get clearCallLog;

  /// No description provided for @newCall.
  ///
  /// In en, this message translates to:
  /// **'New call'**
  String get newCall;

  /// No description provided for @voiceCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voiceCall;

  /// No description provided for @videoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get videoCall;

  /// No description provided for @scheduleACall.
  ///
  /// In en, this message translates to:
  /// **'Schedule a call'**
  String get scheduleACall;

  /// No description provided for @removeFromLog.
  ///
  /// In en, this message translates to:
  /// **'Remove from log'**
  String get removeFromLog;

  /// No description provided for @clearCallLog2.
  ///
  /// In en, this message translates to:
  /// **'Clear call log?'**
  String get clearCallLog2;

  /// No description provided for @everyCallEntryOnThis.
  ///
  /// In en, this message translates to:
  /// **'Every call entry on this device is deleted. Contacts and '**
  String get everyCallEntryOnThis;

  /// No description provided for @clearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get clearLog;

  /// No description provided for @scheduledCalls.
  ///
  /// In en, this message translates to:
  /// **'Scheduled calls'**
  String get scheduledCalls;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @simulated.
  ///
  /// In en, this message translates to:
  /// **'SIMULATED'**
  String get simulated;

  /// No description provided for @favourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favourites;

  /// No description provided for @searchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get searchContacts;

  /// No description provided for @pasteANumber.
  ///
  /// In en, this message translates to:
  /// **'Paste a number'**
  String get pasteANumber;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @remindersFireFromTheLocal.
  ///
  /// In en, this message translates to:
  /// **'Reminders fire from the local notification plugin. They are '**
  String get remindersFireFromTheLocal;

  /// No description provided for @who.
  ///
  /// In en, this message translates to:
  /// **'Who'**
  String get who;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @when.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get when;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @remindMe.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get remindMe;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @scheduleWith.
  ///
  /// In en, this message translates to:
  /// **'Schedule with'**
  String get scheduleWith;

  /// No description provided for @atTheScheduledTime.
  ///
  /// In en, this message translates to:
  /// **'At the scheduled time'**
  String get atTheScheduledTime;

  /// No description provided for @s5MinutesBefore.
  ///
  /// In en, this message translates to:
  /// **'5 minutes before'**
  String get s5MinutesBefore;

  /// No description provided for @s10MinutesBefore.
  ///
  /// In en, this message translates to:
  /// **'10 minutes before'**
  String get s10MinutesBefore;

  /// No description provided for @s30MinutesBefore.
  ///
  /// In en, this message translates to:
  /// **'30 minutes before'**
  String get s30MinutesBefore;

  /// No description provided for @s1HourBefore.
  ///
  /// In en, this message translates to:
  /// **'1 hour before'**
  String get s1HourBefore;

  /// No description provided for @removeReminder.
  ///
  /// In en, this message translates to:
  /// **'Remove reminder?'**
  String get removeReminder;

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

  /// No description provided for @followerGrowth.
  ///
  /// In en, this message translates to:
  /// **'Follower growth'**
  String get followerGrowth;

  /// No description provided for @netNewFollowersPerDay.
  ///
  /// In en, this message translates to:
  /// **'Net new followers per day · last 28 days'**
  String get netNewFollowersPerDay;

  /// No description provided for @postReach.
  ///
  /// In en, this message translates to:
  /// **'Post reach'**
  String get postReach;

  /// No description provided for @postImpressionsPerDayLast.
  ///
  /// In en, this message translates to:
  /// **'Post impressions per day · last 28 days'**
  String get postImpressionsPerDayLast;

  /// No description provided for @reactions.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get reactions;

  /// No description provided for @breakdownAcrossAllPosts.
  ///
  /// In en, this message translates to:
  /// **'Breakdown across all posts'**
  String get breakdownAcrossAllPosts;

  /// No description provided for @topPosts.
  ///
  /// In en, this message translates to:
  /// **'Top posts'**
  String get topPosts;

  /// No description provided for @rankedByViews.
  ///
  /// In en, this message translates to:
  /// **'Ranked by views'**
  String get rankedByViews;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// No description provided for @net28d.
  ///
  /// In en, this message translates to:
  /// **'Net 28d'**
  String get net28d;

  /// No description provided for @reach.
  ///
  /// In en, this message translates to:
  /// **'Reach'**
  String get reach;

  /// No description provided for @noDataForThisPeriod.
  ///
  /// In en, this message translates to:
  /// **'No data for this period yet'**
  String get noDataForThisPeriod;

  /// No description provided for @joinRequests.
  ///
  /// In en, this message translates to:
  /// **'Join requests'**
  String get joinRequests;

  /// No description provided for @noPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get noPendingRequests;

  /// No description provided for @shareTheSecretKeyWith.
  ///
  /// In en, this message translates to:
  /// **'Share the secret key with the people you want to let in. '**
  String get shareTheSecretKeyWith;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @channel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channel;

  /// No description provided for @channelNotFound.
  ///
  /// In en, this message translates to:
  /// **'Channel not found'**
  String get channelNotFound;

  /// No description provided for @itIsNotOnThis.
  ///
  /// In en, this message translates to:
  /// **'It is not on this device and could not be loaded from the '**
  String get itIsNotOnThis;

  /// No description provided for @channelActions.
  ///
  /// In en, this message translates to:
  /// **'Channel actions'**
  String get channelActions;

  /// No description provided for @postToYourChannel.
  ///
  /// In en, this message translates to:
  /// **'Post to your channel'**
  String get postToYourChannel;

  /// No description provided for @writeSomethingForYourFollowers.
  ///
  /// In en, this message translates to:
  /// **'Write something for your followers…'**
  String get writeSomethingForYourFollowers;

  /// No description provided for @deleteThisPost.
  ///
  /// In en, this message translates to:
  /// **'Delete this post?'**
  String get deleteThisPost;

  /// No description provided for @itDisappearsForEveryFollower.
  ///
  /// In en, this message translates to:
  /// **'It disappears for every follower immediately.'**
  String get itDisappearsForEveryFollower;

  /// No description provided for @sendGiftToOwner.
  ///
  /// In en, this message translates to:
  /// **'Send gift to owner'**
  String get sendGiftToOwner;

  /// No description provided for @channelSettings.
  ///
  /// In en, this message translates to:
  /// **'Channel settings'**
  String get channelSettings;

  /// No description provided for @copyInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link'**
  String get copyInviteLink;

  /// No description provided for @showQRCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get showQRCode;

  /// No description provided for @monetized.
  ///
  /// In en, this message translates to:
  /// **'Monetized'**
  String get monetized;

  /// No description provided for @thisChannelIsPrivate.
  ///
  /// In en, this message translates to:
  /// **'This channel is private'**
  String get thisChannelIsPrivate;

  /// No description provided for @postsAreOnlyVisibleTo.
  ///
  /// In en, this message translates to:
  /// **'Posts are only visible to members. Send a request and the owner '**
  String get postsAreOnlyVisibleTo;

  /// No description provided for @requestToJoin.
  ///
  /// In en, this message translates to:
  /// **'Request to join'**
  String get requestToJoin;

  /// No description provided for @premiumChannel.
  ///
  /// In en, this message translates to:
  /// **'Premium channel'**
  String get premiumChannel;

  /// No description provided for @thisChannelIsReservedFor.
  ///
  /// In en, this message translates to:
  /// **'This channel is reserved for premium members. Earn points by '**
  String get thisChannelIsReservedFor;

  /// No description provided for @getPremium.
  ///
  /// In en, this message translates to:
  /// **'Get premium'**
  String get getPremium;

  /// No description provided for @noPostsYet.
  ///
  /// In en, this message translates to:
  /// **'No posts yet'**
  String get noPostsYet;

  /// No description provided for @couldNotLoadThisChannel.
  ///
  /// In en, this message translates to:
  /// **'Could not load this channel'**
  String get couldNotLoadThisChannel;

  /// No description provided for @couldNotLoadPosts.
  ///
  /// In en, this message translates to:
  /// **'Could not load posts'**
  String get couldNotLoadPosts;

  /// No description provided for @couldNotPublishThePost.
  ///
  /// In en, this message translates to:
  /// **'Could not publish the post'**
  String get couldNotPublishThePost;

  /// No description provided for @nSubscribers.
  ///
  /// In en, this message translates to:
  /// **'{count} subscribers'**
  String nSubscribers(int count);

  /// No description provided for @channelInfo.
  ///
  /// In en, this message translates to:
  /// **'Channel info'**
  String get channelInfo;

  /// No description provided for @onlyAdminsCanSendMessages.
  ///
  /// In en, this message translates to:
  /// **'Only admins can send messages in this channel'**
  String get onlyAdminsCanSendMessages;

  /// No description provided for @writeAPost.
  ///
  /// In en, this message translates to:
  /// **'Write a post'**
  String get writeAPost;

  /// No description provided for @writeYourFirstPost.
  ///
  /// In en, this message translates to:
  /// **'Write your first post'**
  String get writeYourFirstPost;

  /// No description provided for @nothingHasBeenPostedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been posted in this channel yet'**
  String get nothingHasBeenPostedYet;

  /// No description provided for @monetization.
  ///
  /// In en, this message translates to:
  /// **'Monetization'**
  String get monetization;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @requirement.
  ///
  /// In en, this message translates to:
  /// **'Requirement'**
  String get requirement;

  /// No description provided for @subscribers.
  ///
  /// In en, this message translates to:
  /// **'Subscribers'**
  String get subscribers;

  /// No description provided for @subscriberProgress.
  ///
  /// In en, this message translates to:
  /// **'Subscriber progress'**
  String get subscriberProgress;

  /// No description provided for @reactionProgress.
  ///
  /// In en, this message translates to:
  /// **'Reaction progress'**
  String get reactionProgress;

  /// No description provided for @estimatedRPM.
  ///
  /// In en, this message translates to:
  /// **'Estimated RPM'**
  String get estimatedRPM;

  /// No description provided for @views.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get views;

  /// No description provided for @estimatedRevenue.
  ///
  /// In en, this message translates to:
  /// **'Estimated revenue'**
  String get estimatedRevenue;

  /// No description provided for @estimatedCostPerView.
  ///
  /// In en, this message translates to:
  /// **'Estimated cost per view'**
  String get estimatedCostPerView;

  /// No description provided for @applyForMonetization.
  ///
  /// In en, this message translates to:
  /// **'Apply for Monetization'**
  String get applyForMonetization;

  /// No description provided for @sendThisChannelForReview.
  ///
  /// In en, this message translates to:
  /// **'Send this channel for review'**
  String get sendThisChannelForReview;

  /// No description provided for @applyForMonetization2.
  ///
  /// In en, this message translates to:
  /// **'Apply for monetization?'**
  String get applyForMonetization2;

  /// No description provided for @yourChannelMeetsTheRequirements.
  ///
  /// In en, this message translates to:
  /// **'Your channel meets the requirements. A reviewer will '**
  String get yourChannelMeetsTheRequirements;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @ownerTools.
  ///
  /// In en, this message translates to:
  /// **'Owner tools'**
  String get ownerTools;

  /// No description provided for @followerGrowthReachAndReactions.
  ///
  /// In en, this message translates to:
  /// **'Follower growth, reach and reactions over 28 days'**
  String get followerGrowthReachAndReactions;

  /// No description provided for @tapToChangeTheChannel.
  ///
  /// In en, this message translates to:
  /// **'Tap to change the channel photo'**
  String get tapToChangeTheChannel;

  /// No description provided for @identity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identity;

  /// No description provided for @channelName.
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get channelName;

  /// No description provided for @approveOrRejectPeopleWho.
  ///
  /// In en, this message translates to:
  /// **'Approve or reject people who have the key'**
  String get approveOrRejectPeopleWho;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @rotateTheSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Rotate the secret key?'**
  String get rotateTheSecretKey;

  /// No description provided for @everyoneCurrentlyUsingTheOld.
  ///
  /// In en, this message translates to:
  /// **'Everyone currently using the old key keeps their access, but '**
  String get everyoneCurrentlyUsingTheOld;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @aReviewerWillCheckThat.
  ///
  /// In en, this message translates to:
  /// **'A reviewer will check that your channel meets the '**
  String get aReviewerWillCheckThat;

  /// No description provided for @monetizationReview.
  ///
  /// In en, this message translates to:
  /// **'Monetization review'**
  String get monetizationReview;

  /// No description provided for @reviewersOnly.
  ///
  /// In en, this message translates to:
  /// **'Reviewers only'**
  String get reviewersOnly;

  /// No description provided for @thisScreenIsLimitedTo.
  ///
  /// In en, this message translates to:
  /// **'This screen is limited to project reviewers.'**
  String get thisScreenIsLimitedTo;

  /// No description provided for @nothingToReview.
  ///
  /// In en, this message translates to:
  /// **'Nothing to review'**
  String get nothingToReview;

  /// No description provided for @channelsAppearHereOnceThey.
  ///
  /// In en, this message translates to:
  /// **'Channels appear here once they pass the follower and reaction '**
  String get channelsAppearHereOnceThey;

  /// No description provided for @channelPhoto.
  ///
  /// In en, this message translates to:
  /// **'Channel photo'**
  String get channelPhoto;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @secretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret key'**
  String get secretKey;

  /// No description provided for @copyClose.
  ///
  /// In en, this message translates to:
  /// **'Copy & close'**
  String get copyClose;

  /// No description provided for @archiveActions.
  ///
  /// In en, this message translates to:
  /// **'Archive actions'**
  String get archiveActions;

  /// No description provided for @markAllAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllAsRead;

  /// No description provided for @unarchiveAll.
  ///
  /// In en, this message translates to:
  /// **'Unarchive all'**
  String get unarchiveAll;

  /// No description provided for @nothingArchived.
  ///
  /// In en, this message translates to:
  /// **'Nothing archived'**
  String get nothingArchived;

  /// No description provided for @archivedChatsAreHiddenFrom.
  ///
  /// In en, this message translates to:
  /// **'Archived chats are hidden from the main list but keep all '**
  String get archivedChatsAreHiddenFrom;

  /// No description provided for @newList.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get newList;

  /// No description provided for @aBroadcastSendsAnIndividual.
  ///
  /// In en, this message translates to:
  /// **'A broadcast sends an individual copy of your message to each '**
  String get aBroadcastSendsAnIndividual;

  /// No description provided for @noBroadcastLists.
  ///
  /// In en, this message translates to:
  /// **'No broadcast lists'**
  String get noBroadcastLists;

  /// No description provided for @createAListOfUp.
  ///
  /// In en, this message translates to:
  /// **'Create a list of up to 256 recipients and message them '**
  String get createAListOfUp;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameList.
  ///
  /// In en, this message translates to:
  /// **'Rename list'**
  String get renameList;

  /// No description provided for @listName.
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get listName;

  /// No description provided for @editRecipients.
  ///
  /// In en, this message translates to:
  /// **'Edit recipients'**
  String get editRecipients;

  /// No description provided for @deleteList.
  ///
  /// In en, this message translates to:
  /// **'Delete list'**
  String get deleteList;

  /// No description provided for @theListIsDeletedExisting.
  ///
  /// In en, this message translates to:
  /// **'The list is deleted. Existing conversations with its '**
  String get theListIsDeletedExisting;

  /// No description provided for @newBroadcastList.
  ///
  /// In en, this message translates to:
  /// **'New broadcast list'**
  String get newBroadcastList;

  /// No description provided for @addRecipients.
  ///
  /// In en, this message translates to:
  /// **'Add recipients'**
  String get addRecipients;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @sendABroadcast.
  ///
  /// In en, this message translates to:
  /// **'Send a broadcast'**
  String get sendABroadcast;

  /// No description provided for @localStorageCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'Local storage could not be opened, so your chats, contacts '**
  String get localStorageCouldNotBe;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @noChatsFound.
  ///
  /// In en, this message translates to:
  /// **'No chats found'**
  String get noChatsFound;

  /// No description provided for @tryADifferentNameOr.
  ///
  /// In en, this message translates to:
  /// **'Try a different name or keyword.'**
  String get tryADifferentNameOr;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @saveSomeoneToThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Save someone to this device'**
  String get saveSomeoneToThisDevice;

  /// No description provided for @broadcastToAnUnlimitedAudience.
  ///
  /// In en, this message translates to:
  /// **'Broadcast to an unlimited audience'**
  String get broadcastToAnUnlimitedAudience;

  /// No description provided for @groupRelatedChatsTogether.
  ///
  /// In en, this message translates to:
  /// **'Group related chats together'**
  String get groupRelatedChatsTogether;

  /// No description provided for @contactsOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Contacts on this device'**
  String get contactsOnThisDevice;

  /// No description provided for @newBroadcast.
  ///
  /// In en, this message translates to:
  /// **'New broadcast'**
  String get newBroadcast;

  /// No description provided for @forwardTo.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get forwardTo;

  /// No description provided for @viewContact.
  ///
  /// In en, this message translates to:
  /// **'View contact'**
  String get viewContact;

  /// No description provided for @sendGift.
  ///
  /// In en, this message translates to:
  /// **'Send gift'**
  String get sendGift;

  /// No description provided for @mediaLinksAndDocs.
  ///
  /// In en, this message translates to:
  /// **'Media, links and docs'**
  String get mediaLinksAndDocs;

  /// No description provided for @searchInChat.
  ///
  /// In en, this message translates to:
  /// **'Search in chat'**
  String get searchInChat;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @saveAttachment.
  ///
  /// In en, this message translates to:
  /// **'Save attachment'**
  String get saveAttachment;

  /// No description provided for @cancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// No description provided for @pinnedMessage.
  ///
  /// In en, this message translates to:
  /// **'Pinned message'**
  String get pinnedMessage;

  /// No description provided for @mediaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Media unavailable'**
  String get mediaUnavailable;

  /// No description provided for @thisImageCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'This image could not be opened'**
  String get thisImageCouldNotBe;

  /// No description provided for @thisFileIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'This file is no longer on the device'**
  String get thisFileIsNoLonger;

  /// No description provided for @couldNotLoadThisAttachment.
  ///
  /// In en, this message translates to:
  /// **'Could not load this attachment'**
  String get couldNotLoadThisAttachment;

  /// No description provided for @unstarAll.
  ///
  /// In en, this message translates to:
  /// **'Unstar all'**
  String get unstarAll;

  /// No description provided for @searchStarredMessages.
  ///
  /// In en, this message translates to:
  /// **'Search starred messages'**
  String get searchStarredMessages;

  /// No description provided for @openChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get openChat;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @removeStar.
  ///
  /// In en, this message translates to:
  /// **'Remove star'**
  String get removeStar;

  /// No description provided for @removeAllStars.
  ///
  /// In en, this message translates to:
  /// **'Remove all stars?'**
  String get removeAllStars;

  /// No description provided for @messageInfo.
  ///
  /// In en, this message translates to:
  /// **'Message info'**
  String get messageInfo;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @addOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get addOption;

  /// No description provided for @allowMultipleAnswers.
  ///
  /// In en, this message translates to:
  /// **'Allow multiple answers'**
  String get allowMultipleAnswers;

  /// No description provided for @createEvent.
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get createEvent;

  /// No description provided for @eventName.
  ///
  /// In en, this message translates to:
  /// **'Event name'**
  String get eventName;

  /// No description provided for @stickers.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get stickers;

  /// No description provided for @clearThisChat.
  ///
  /// In en, this message translates to:
  /// **'Clear this chat?'**
  String get clearThisChat;

  /// No description provided for @allMessagesInThisConversation.
  ///
  /// In en, this message translates to:
  /// **'All messages in this conversation will be removed from this device. '**
  String get allMessagesInThisConversation;

  /// No description provided for @noEmojiFound.
  ///
  /// In en, this message translates to:
  /// **'No emoji found'**
  String get noEmojiFound;

  /// No description provided for @tryAnotherKeyword.
  ///
  /// In en, this message translates to:
  /// **'Try another keyword.'**
  String get tryAnotherKeyword;

  /// No description provided for @frequentlyUsed.
  ///
  /// In en, this message translates to:
  /// **'Frequently used'**
  String get frequentlyUsed;

  /// No description provided for @searchEmoji.
  ///
  /// In en, this message translates to:
  /// **'Search emoji'**
  String get searchEmoji;

  /// No description provided for @deleteForMe.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get deleteForMe;

  /// No description provided for @deleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForEveryone;

  /// No description provided for @saveToDevice.
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get saveToDevice;

  /// No description provided for @locationPreview.
  ///
  /// In en, this message translates to:
  /// **'Location preview'**
  String get locationPreview;

  /// No description provided for @event2.
  ///
  /// In en, this message translates to:
  /// **'EVENT'**
  String get event2;

  /// No description provided for @going.
  ///
  /// In en, this message translates to:
  /// **'Going'**
  String get going;

  /// No description provided for @maybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get maybe;

  /// No description provided for @emoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emoji;

  /// No description provided for @attach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attach;

  /// No description provided for @holdToRecordAVoice.
  ///
  /// In en, this message translates to:
  /// **'Hold to record a voice note'**
  String get holdToRecordAVoice;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @editingMessage.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get editingMessage;

  /// No description provided for @noCommunitiesYet.
  ///
  /// In en, this message translates to:
  /// **'No communities yet'**
  String get noCommunitiesYet;

  /// No description provided for @aCommunityGroupsRelatedChats.
  ///
  /// In en, this message translates to:
  /// **'A community groups related chats under one announcement channel. '**
  String get aCommunityGroupsRelatedChats;

  /// No description provided for @communityActions.
  ///
  /// In en, this message translates to:
  /// **'Community actions'**
  String get communityActions;

  /// No description provided for @openCommunity.
  ///
  /// In en, this message translates to:
  /// **'Open community'**
  String get openCommunity;

  /// No description provided for @openChannel.
  ///
  /// In en, this message translates to:
  /// **'Open channel'**
  String get openChannel;

  /// No description provided for @unfollow.
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get unfollow;

  /// No description provided for @deleteCommunity.
  ///
  /// In en, this message translates to:
  /// **'Delete community'**
  String get deleteCommunity;

  /// No description provided for @theCommunityAndItsAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'The community and its announcement group are removed from '**
  String get theCommunityAndItsAnnouncement;

  /// No description provided for @noChannelsYet.
  ///
  /// In en, this message translates to:
  /// **'No channels yet'**
  String get noChannelsYet;

  /// No description provided for @channelsBroadcastOneWayTo.
  ///
  /// In en, this message translates to:
  /// **'Channels broadcast one-way to followers. Create one, or follow a '**
  String get channelsBroadcastOneWayTo;

  /// No description provided for @community.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get community;

  /// No description provided for @communityNotFound.
  ///
  /// In en, this message translates to:
  /// **'Community not found'**
  String get communityNotFound;

  /// No description provided for @itWasDeletedFromThis.
  ///
  /// In en, this message translates to:
  /// **'It was deleted from this device.'**
  String get itWasDeletedFromThis;

  /// No description provided for @tapToEdit.
  ///
  /// In en, this message translates to:
  /// **'Tap to edit'**
  String get tapToEdit;

  /// No description provided for @groupsInThisCommunity.
  ///
  /// In en, this message translates to:
  /// **'Groups in this community'**
  String get groupsInThisCommunity;

  /// No description provided for @createAGroupHere.
  ///
  /// In en, this message translates to:
  /// **'Create a group here'**
  String get createAGroupHere;

  /// No description provided for @newGroupThatIsAutomatically.
  ///
  /// In en, this message translates to:
  /// **'New group that is automatically part of this community'**
  String get newGroupThatIsAutomatically;

  /// No description provided for @addExistingGroups.
  ///
  /// In en, this message translates to:
  /// **'Add existing groups'**
  String get addExistingGroups;

  /// No description provided for @linkGroupsYouAlreadyCreated.
  ///
  /// In en, this message translates to:
  /// **'Link groups you already created'**
  String get linkGroupsYouAlreadyCreated;

  /// No description provided for @invitePeople.
  ///
  /// In en, this message translates to:
  /// **'Invite people'**
  String get invitePeople;

  /// No description provided for @addContactsToThisCommunity.
  ///
  /// In en, this message translates to:
  /// **'Add contacts to this community'**
  String get addContactsToThisCommunity;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @removeTheCommunityAndIts.
  ///
  /// In en, this message translates to:
  /// **'Remove the community and its announcement group'**
  String get removeTheCommunityAndIts;

  /// No description provided for @communityName.
  ///
  /// In en, this message translates to:
  /// **'Community name'**
  String get communityName;

  /// No description provided for @communityDescription.
  ///
  /// In en, this message translates to:
  /// **'Community description'**
  String get communityDescription;

  /// No description provided for @whatIsThisCommunityAbout.
  ///
  /// In en, this message translates to:
  /// **'What is this community about?'**
  String get whatIsThisCommunityAbout;

  /// No description provided for @addGroups.
  ///
  /// In en, this message translates to:
  /// **'Add groups'**
  String get addGroups;

  /// No description provided for @theCommunityIsRemovedFrom.
  ///
  /// In en, this message translates to:
  /// **'The community is removed from this device. Groups inside it stay '**
  String get theCommunityIsRemovedFrom;

  /// No description provided for @addACommunityPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a community photo'**
  String get addACommunityPhoto;

  /// No description provided for @addMembers.
  ///
  /// In en, this message translates to:
  /// **'Add members'**
  String get addMembers;

  /// No description provided for @syncDeviceContacts.
  ///
  /// In en, this message translates to:
  /// **'Sync device contacts'**
  String get syncDeviceContacts;

  /// No description provided for @contactNotFound.
  ///
  /// In en, this message translates to:
  /// **'Contact not found'**
  String get contactNotFound;

  /// No description provided for @thisPersonIsNotIn.
  ///
  /// In en, this message translates to:
  /// **'This person is not in your contacts and has no Imo LIVE '**
  String get thisPersonIsNotIn;

  /// No description provided for @contactInfo.
  ///
  /// In en, this message translates to:
  /// **'Contact info'**
  String get contactInfo;

  /// No description provided for @editContact.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get editContact;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @mediaActivity.
  ///
  /// In en, this message translates to:
  /// **'Media & activity'**
  String get mediaActivity;

  /// No description provided for @sharedMedia.
  ///
  /// In en, this message translates to:
  /// **'Shared media'**
  String get sharedMedia;

  /// No description provided for @mediaAttachesToConversationsOpen.
  ///
  /// In en, this message translates to:
  /// **'Media attaches to conversations. Open the chat and use '**
  String get mediaAttachesToConversationsOpen;

  /// No description provided for @statusUpdates.
  ///
  /// In en, this message translates to:
  /// **'Status updates'**
  String get statusUpdates;

  /// No description provided for @muteAlertsForThisConversation.
  ///
  /// In en, this message translates to:
  /// **'Mute alerts for this conversation'**
  String get muteAlertsForThisConversation;

  /// No description provided for @openTheChatAndChoose.
  ///
  /// In en, this message translates to:
  /// **'Open the chat and choose Disappearing messages '**
  String get openTheChatAndChoose;

  /// No description provided for @removesThisConversationAndIts.
  ///
  /// In en, this message translates to:
  /// **'Removes this conversation and its messages'**
  String get removesThisConversationAndIts;

  /// No description provided for @deleteChat2.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get deleteChat2;

  /// No description provided for @deleteContact.
  ///
  /// In en, this message translates to:
  /// **'Delete contact'**
  String get deleteContact;

  /// No description provided for @theContactIsRemovedFrom.
  ///
  /// In en, this message translates to:
  /// **'The contact is removed from your list. Existing chats '**
  String get theContactIsRemovedFrom;

  /// No description provided for @shareContact.
  ///
  /// In en, this message translates to:
  /// **'Share contact'**
  String get shareContact;

  /// No description provided for @copyPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy phone number'**
  String get copyPhoneNumber;

  /// No description provided for @chooseACountry.
  ///
  /// In en, this message translates to:
  /// **'Choose a country'**
  String get chooseACountry;

  /// No description provided for @searchCountryCodeOrDial.
  ///
  /// In en, this message translates to:
  /// **'Search country, code or dial prefix'**
  String get searchCountryCodeOrDial;

  /// No description provided for @numberAlreadySaved.
  ///
  /// In en, this message translates to:
  /// **'Number already saved'**
  String get numberAlreadySaved;

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get saveAnyway;

  /// No description provided for @deleteContact2.
  ///
  /// In en, this message translates to:
  /// **'Delete contact?'**
  String get deleteContact2;

  /// No description provided for @inviteToImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'Invite to Imo LIVE'**
  String get inviteToImoLIVE;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @favouritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Favourites only'**
  String get favouritesOnly;

  /// No description provided for @addressBookUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Address book unavailable'**
  String get addressBookUnavailable;

  /// No description provided for @imoLIVECouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE could not read your device contacts. Grant the contacts '**
  String get imoLIVECouldNotRead;

  /// No description provided for @newMessagesInThisChat.
  ///
  /// In en, this message translates to:
  /// **'New messages in this chat will disappear after the '**
  String get newMessagesInThisChat;

  /// No description provided for @thisNumberIsNotOn.
  ///
  /// In en, this message translates to:
  /// **'This number is not on Imo LIVE yet. Invite them?'**
  String get thisNumberIsNotOn;

  /// No description provided for @redeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get redeem;

  /// No description provided for @watchToEarn.
  ///
  /// In en, this message translates to:
  /// **'Watch to Earn'**
  String get watchToEarn;

  /// No description provided for @yourPoints.
  ///
  /// In en, this message translates to:
  /// **'Your points'**
  String get yourPoints;

  /// No description provided for @premium.
  ///
  /// In en, this message translates to:
  /// **'PREMIUM'**
  String get premium;

  /// No description provided for @watchEarn.
  ///
  /// In en, this message translates to:
  /// **'Watch & Earn'**
  String get watchEarn;

  /// No description provided for @premium2.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get premium2;

  /// No description provided for @noAds.
  ///
  /// In en, this message translates to:
  /// **'No ads'**
  String get noAds;

  /// No description provided for @nothingToWatchBeforeYour.
  ///
  /// In en, this message translates to:
  /// **'Nothing to watch before your content'**
  String get nothingToWatchBeforeYour;

  /// No description provided for @exclusiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Exclusive badge'**
  String get exclusiveBadge;

  /// No description provided for @aPremiumMarkOnYour.
  ///
  /// In en, this message translates to:
  /// **'A premium mark on your profile'**
  String get aPremiumMarkOnYour;

  /// No description provided for @premiumChannels.
  ///
  /// In en, this message translates to:
  /// **'Premium channels'**
  String get premiumChannels;

  /// No description provided for @openChannelsReservedForMembers.
  ///
  /// In en, this message translates to:
  /// **'Open channels reserved for members'**
  String get openChannelsReservedForMembers;

  /// No description provided for @earningHistory.
  ///
  /// In en, this message translates to:
  /// **'Earning history'**
  String get earningHistory;

  /// No description provided for @couldNotLoadYourHistory.
  ///
  /// In en, this message translates to:
  /// **'Could not load your history.'**
  String get couldNotLoadYourHistory;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// No description provided for @watchYourFirstAdTo.
  ///
  /// In en, this message translates to:
  /// **'Watch your first ad to start earning.'**
  String get watchYourFirstAdTo;

  /// No description provided for @couldNotLoadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications'**
  String get couldNotLoadNotifications;

  /// No description provided for @checkYourConnectionAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get checkYourConnectionAndTry;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// No description provided for @giftsYouReceiveWillShow.
  ///
  /// In en, this message translates to:
  /// **'Gifts you receive will show up here.'**
  String get giftsYouReceiveWillShow;

  /// No description provided for @groupInfo.
  ///
  /// In en, this message translates to:
  /// **'Group info'**
  String get groupInfo;

  /// No description provided for @groupNotFound.
  ///
  /// In en, this message translates to:
  /// **'Group not found'**
  String get groupNotFound;

  /// No description provided for @thisGroupWasDeletedOr.
  ///
  /// In en, this message translates to:
  /// **'This group was deleted or never existed on this device.'**
  String get thisGroupWasDeletedOr;

  /// No description provided for @editGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get editGroup;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @groupSettings.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettings;

  /// No description provided for @muteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get muteNotifications;

  /// No description provided for @silenceAlertsForThisGroup.
  ///
  /// In en, this message translates to:
  /// **'Silence alerts for this group'**
  String get silenceAlertsForThisGroup;

  /// No description provided for @openTheConversationAndTap.
  ///
  /// In en, this message translates to:
  /// **'Open the conversation and tap the search icon to filter '**
  String get openTheConversationAndTap;

  /// No description provided for @adminPermissions.
  ///
  /// In en, this message translates to:
  /// **'Admin permissions'**
  String get adminPermissions;

  /// No description provided for @sendMessages.
  ///
  /// In en, this message translates to:
  /// **'Send messages'**
  String get sendMessages;

  /// No description provided for @allowMembersToSendMessages.
  ///
  /// In en, this message translates to:
  /// **'Allow members to send messages in the group'**
  String get allowMembersToSendMessages;

  /// No description provided for @editGroupInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit group info'**
  String get editGroupInfo;

  /// No description provided for @allowMembersToChangeThe.
  ///
  /// In en, this message translates to:
  /// **'Allow members to change the name, photo and description'**
  String get allowMembersToChangeThe;

  /// No description provided for @allowMembersToAddOther.
  ///
  /// In en, this message translates to:
  /// **'Allow members to add other people'**
  String get allowMembersToAddOther;

  /// No description provided for @inviteViaLink.
  ///
  /// In en, this message translates to:
  /// **'Invite via link'**
  String get inviteViaLink;

  /// No description provided for @anyoneWithTheInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the invite link can join'**
  String get anyoneWithTheInviteLink;

  /// No description provided for @approveNewMembers.
  ///
  /// In en, this message translates to:
  /// **'Approve new members'**
  String get approveNewMembers;

  /// No description provided for @adminsMustApproveEveryoneWho.
  ///
  /// In en, this message translates to:
  /// **'Admins must approve everyone who tries to join'**
  String get adminsMustApproveEveryoneWho;

  /// No description provided for @theInviteCodeIsGenerated.
  ///
  /// In en, this message translates to:
  /// **'The invite code is generated locally. Joining via a link needs '**
  String get theInviteCodeIsGenerated;

  /// No description provided for @resetInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Reset invite link'**
  String get resetInviteLink;

  /// No description provided for @invalidateTheCurrentCodeAnd.
  ///
  /// In en, this message translates to:
  /// **'Invalidate the current code and issue a new one'**
  String get invalidateTheCurrentCodeAnd;

  /// No description provided for @invalidatingAnInviteLinkIs.
  ///
  /// In en, this message translates to:
  /// **'Invalidating an invite link is a server action — old '**
  String get invalidatingAnInviteLinkIs;

  /// No description provided for @clearMessages.
  ///
  /// In en, this message translates to:
  /// **'Clear messages'**
  String get clearMessages;

  /// No description provided for @deleteEveryMessageInThis.
  ///
  /// In en, this message translates to:
  /// **'Delete every message in this group, keeping the group'**
  String get deleteEveryMessageInThis;

  /// No description provided for @clearAllMessages.
  ///
  /// In en, this message translates to:
  /// **'Clear all messages?'**
  String get clearAllMessages;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @removeTheGroupAndIts.
  ///
  /// In en, this message translates to:
  /// **'Remove the group and its entire history'**
  String get removeTheGroupAndIts;

  /// No description provided for @whatIsThisGroupAbout.
  ///
  /// In en, this message translates to:
  /// **'What is this group about?'**
  String get whatIsThisGroupAbout;

  /// No description provided for @addMembersDirectly.
  ///
  /// In en, this message translates to:
  /// **'Add members directly'**
  String get addMembersDirectly;

  /// No description provided for @removeFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// No description provided for @youLeaveTheGroupYour.
  ///
  /// In en, this message translates to:
  /// **'You leave the group. Your existing messages stay in the conversation '**
  String get youLeaveTheGroupYour;

  /// No description provided for @theGroupItsMembersAnd.
  ///
  /// In en, this message translates to:
  /// **'The group, its members and every message are permanently deleted '**
  String get theGroupItsMembersAnd;

  /// No description provided for @noMembersYet.
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get noMembersYet;

  /// No description provided for @aGroupNeedsAtLeast.
  ///
  /// In en, this message translates to:
  /// **'A group needs at least one other person. You will be added '**
  String get aGroupNeedsAtLeast;

  /// No description provided for @youWillBeTheGroup.
  ///
  /// In en, this message translates to:
  /// **'You will be the group admin'**
  String get youWillBeTheGroup;

  /// No description provided for @adminsCanAddOrRemove.
  ///
  /// In en, this message translates to:
  /// **'Admins can add or remove members, edit the group photo, '**
  String get adminsCanAddOrRemove;

  /// No description provided for @imoLIVESyncsThroughFirebase.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE syncs through Firebase — Authentication and Cloud '**
  String get imoLIVESyncsThroughFirebase;

  /// No description provided for @build.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get build;

  /// No description provided for @appName2.
  ///
  /// In en, this message translates to:
  /// **'App name'**
  String get appName2;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @architecture.
  ///
  /// In en, this message translates to:
  /// **'Architecture'**
  String get architecture;

  /// No description provided for @imoLIVEFollowsAClean.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE follows a clean, feature-first layout.'**
  String get imoLIVEFollowsAClean;

  /// No description provided for @everyScreenDependsOnAn.
  ///
  /// In en, this message translates to:
  /// **'Every screen depends on an abstract repository interface. Chats '**
  String get everyScreenDependsOnAn;

  /// No description provided for @whatStillNeedsConfiguring.
  ///
  /// In en, this message translates to:
  /// **'What still needs configuring'**
  String get whatStillNeedsConfiguring;

  /// No description provided for @everythingBelowAlreadyHasIts.
  ///
  /// In en, this message translates to:
  /// **'Everything below already has its interface and local '**
  String get everythingBelowAlreadyHasIts;

  /// No description provided for @searchEverything.
  ///
  /// In en, this message translates to:
  /// **'Search everything'**
  String get searchEverything;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @searchIn.
  ///
  /// In en, this message translates to:
  /// **'Search in'**
  String get searchIn;

  /// No description provided for @everything.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get everything;

  /// No description provided for @messages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @inYourContacts.
  ///
  /// In en, this message translates to:
  /// **'In your contacts'**
  String get inYourContacts;

  /// No description provided for @onImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'On Imo LIVE'**
  String get onImoLIVE;

  /// No description provided for @frequentlyAsked.
  ///
  /// In en, this message translates to:
  /// **'Frequently asked'**
  String get frequentlyAsked;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @theCodeCarriesAnImo.
  ///
  /// In en, this message translates to:
  /// **'The code carries an Imo LIVE identifier. Another person can '**
  String get theCodeCarriesAnImo;

  /// No description provided for @shareCode.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get shareCode;

  /// No description provided for @fromImoLIVEINC.
  ///
  /// In en, this message translates to:
  /// **'From Imo LIVE, INC'**
  String get fromImoLIVEINC;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @yourNameIsVisibleTo.
  ///
  /// In en, this message translates to:
  /// **'Your name is visible to everyone you message.'**
  String get yourNameIsVisibleTo;

  /// No description provided for @requiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredLabel;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @about2.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get about2;

  /// No description provided for @writeSomethingAboutYourself.
  ///
  /// In en, this message translates to:
  /// **'Write something about yourself'**
  String get writeSomethingAboutYourself;

  /// No description provided for @myQRCode.
  ///
  /// In en, this message translates to:
  /// **'My QR code'**
  String get myQRCode;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeen;

  /// No description provided for @searchImoLIVEBy.
  ///
  /// In en, this message translates to:
  /// **'Search Imo LIVE by'**
  String get searchImoLIVEBy;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @userID.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get userID;

  /// No description provided for @theUidShownOnA.
  ///
  /// In en, this message translates to:
  /// **'The uid shown on a profile'**
  String get theUidShownOnA;

  /// No description provided for @searchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Search unavailable'**
  String get searchUnavailable;

  /// No description provided for @imoLIVECouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE could not be reached. Check your connection and '**
  String get imoLIVECouldNotBe;

  /// No description provided for @inviteThemToImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'Invite them to Imo LIVE and you can start chatting as soon '**
  String get inviteThemToImoLIVE;

  /// No description provided for @passkeys.
  ///
  /// In en, this message translates to:
  /// **'Passkeys'**
  String get passkeys;

  /// No description provided for @enterANewPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a new phone number (stored locally only)'**
  String get enterANewPhoneNumber;

  /// No description provided for @verifiedNumber.
  ///
  /// In en, this message translates to:
  /// **'Verified number'**
  String get verifiedNumber;

  /// No description provided for @accountActivity.
  ///
  /// In en, this message translates to:
  /// **'Account activity'**
  String get accountActivity;

  /// No description provided for @clearAllLocalData.
  ///
  /// In en, this message translates to:
  /// **'Clear all local data'**
  String get clearAllLocalData;

  /// No description provided for @deletesChatsMessagesContactsStatuses.
  ///
  /// In en, this message translates to:
  /// **'Deletes chats, messages, contacts, statuses and settings '**
  String get deletesChatsMessagesContactsStatuses;

  /// No description provided for @clearAllLocalData2.
  ///
  /// In en, this message translates to:
  /// **'Clear all local data?'**
  String get clearAllLocalData2;

  /// No description provided for @everyChatMessageContactAnd.
  ///
  /// In en, this message translates to:
  /// **'Every chat, message, contact and setting stored by Imo '**
  String get everyChatMessageContactAnd;

  /// No description provided for @clearEverything.
  ///
  /// In en, this message translates to:
  /// **'Clear everything'**
  String get clearEverything;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @restoreDefaultAppearance.
  ///
  /// In en, this message translates to:
  /// **'Restore default appearance'**
  String get restoreDefaultAppearance;

  /// No description provided for @darkThemeRoseAccent100.
  ///
  /// In en, this message translates to:
  /// **'Dark theme, rose accent, 100% text size'**
  String get darkThemeRoseAccent100;

  /// No description provided for @blockAContact.
  ///
  /// In en, this message translates to:
  /// **'Block a contact'**
  String get blockAContact;

  /// No description provided for @blockedContactsCannotMessageOr.
  ///
  /// In en, this message translates to:
  /// **'Blocked contacts cannot message or call you from this '**
  String get blockedContactsCannotMessageOr;

  /// No description provided for @unblockingRestoresTheContactTo.
  ///
  /// In en, this message translates to:
  /// **'Unblocking restores the contact to your chat list and '**
  String get unblockingRestoresTheContactTo;

  /// No description provided for @unknownSenders.
  ///
  /// In en, this message translates to:
  /// **'Unknown senders'**
  String get unknownSenders;

  /// No description provided for @blockUnknownSenders.
  ///
  /// In en, this message translates to:
  /// **'Block unknown senders'**
  String get blockUnknownSenders;

  /// No description provided for @blockedCallers.
  ///
  /// In en, this message translates to:
  /// **'Blocked callers'**
  String get blockedCallers;

  /// No description provided for @blockedContactsAreAlsoPrevented.
  ///
  /// In en, this message translates to:
  /// **'Blocked contacts are also prevented from calling'**
  String get blockedContactsAreAlsoPrevented;

  /// No description provided for @display.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// No description provided for @enterKeySendsMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter key sends message'**
  String get enterKeySendsMessage;

  /// No description provided for @pressEnterToSendInstead.
  ///
  /// In en, this message translates to:
  /// **'Press Enter to send instead of adding a new line'**
  String get pressEnterToSendInstead;

  /// No description provided for @mediaVisibility.
  ///
  /// In en, this message translates to:
  /// **'Media visibility'**
  String get mediaVisibility;

  /// No description provided for @showNewlyDownloadedMediaIn.
  ///
  /// In en, this message translates to:
  /// **'Show newly downloaded media in your device gallery'**
  String get showNewlyDownloadedMediaIn;

  /// No description provided for @chatHistory.
  ///
  /// In en, this message translates to:
  /// **'Chat history'**
  String get chatHistory;

  /// No description provided for @keepChatsArchived.
  ///
  /// In en, this message translates to:
  /// **'Keep chats archived'**
  String get keepChatsArchived;

  /// No description provided for @newMessagesStayInThe.
  ///
  /// In en, this message translates to:
  /// **'New messages stay in the archive instead of returning the '**
  String get newMessagesStayInThe;

  /// No description provided for @chatBackup.
  ///
  /// In en, this message translates to:
  /// **'Chat backup'**
  String get chatBackup;

  /// No description provided for @backUpOver.
  ///
  /// In en, this message translates to:
  /// **'Back up over'**
  String get backUpOver;

  /// No description provided for @daily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get daily;

  /// No description provided for @weekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get weekly;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @autoDownload.
  ///
  /// In en, this message translates to:
  /// **'Auto-download'**
  String get autoDownload;

  /// No description provided for @appliesToMediaYouReceive.
  ///
  /// In en, this message translates to:
  /// **'Applies to media you receive while on a mobile or Wi-Fi network.'**
  String get appliesToMediaYouReceive;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @housekeeping.
  ///
  /// In en, this message translates to:
  /// **'Housekeeping'**
  String get housekeeping;

  /// No description provided for @resetChatSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset chat settings'**
  String get resetChatSettings;

  /// No description provided for @restoreEveryChatPreferenceTo.
  ///
  /// In en, this message translates to:
  /// **'Restore every chat preference to its default'**
  String get restoreEveryChatPreferenceTo;

  /// No description provided for @resetChatSettings2.
  ///
  /// In en, this message translates to:
  /// **'Reset chat settings?'**
  String get resetChatSettings2;

  /// No description provided for @chatPreferencesReturnToTheir.
  ///
  /// In en, this message translates to:
  /// **'Chat preferences return to their defaults. No chats or '**
  String get chatPreferencesReturnToTheir;

  /// No description provided for @syncContactsOnSave.
  ///
  /// In en, this message translates to:
  /// **'Sync contacts on save'**
  String get syncContactsOnSave;

  /// No description provided for @offerToAddANumber.
  ///
  /// In en, this message translates to:
  /// **'Offer to add a number to your device address book when you '**
  String get offerToAddANumber;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @appDisplayLanguage.
  ///
  /// In en, this message translates to:
  /// **'App display language'**
  String get appDisplayLanguage;

  /// No description provided for @translationsAreBundledWithThe.
  ///
  /// In en, this message translates to:
  /// **'Translations are bundled with the app as ARB resources. '**
  String get translationsAreBundledWithThe;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @switchAnyway.
  ///
  /// In en, this message translates to:
  /// **'Switch anyway'**
  String get switchAnyway;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @bangladesh.
  ///
  /// In en, this message translates to:
  /// **'Bangladesh'**
  String get bangladesh;

  /// No description provided for @dialCode880.
  ///
  /// In en, this message translates to:
  /// **'Dial code +880'**
  String get dialCode880;

  /// No description provided for @india.
  ///
  /// In en, this message translates to:
  /// **'India'**
  String get india;

  /// No description provided for @dialCode91.
  ///
  /// In en, this message translates to:
  /// **'Dial code +91'**
  String get dialCode91;

  /// No description provided for @unitedStates.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get unitedStates;

  /// No description provided for @dialCode1.
  ///
  /// In en, this message translates to:
  /// **'Dial code +1'**
  String get dialCode1;

  /// No description provided for @unitedKingdom.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get unitedKingdom;

  /// No description provided for @dialCode44.
  ///
  /// In en, this message translates to:
  /// **'Dial code +44'**
  String get dialCode44;

  /// No description provided for @pakistan.
  ///
  /// In en, this message translates to:
  /// **'Pakistan'**
  String get pakistan;

  /// No description provided for @dialCode92.
  ///
  /// In en, this message translates to:
  /// **'Dial code +92'**
  String get dialCode92;

  /// No description provided for @unitedArabEmirates.
  ///
  /// In en, this message translates to:
  /// **'United Arab Emirates'**
  String get unitedArabEmirates;

  /// No description provided for @dialCode971.
  ///
  /// In en, this message translates to:
  /// **'Dial code +971'**
  String get dialCode971;

  /// No description provided for @saudiArabia.
  ///
  /// In en, this message translates to:
  /// **'Saudi Arabia'**
  String get saudiArabia;

  /// No description provided for @dialCode966.
  ///
  /// In en, this message translates to:
  /// **'Dial code +966'**
  String get dialCode966;

  /// No description provided for @indonesia.
  ///
  /// In en, this message translates to:
  /// **'Indonesia'**
  String get indonesia;

  /// No description provided for @dialCode62.
  ///
  /// In en, this message translates to:
  /// **'Dial code +62'**
  String get dialCode62;

  /// No description provided for @timeFormat.
  ///
  /// In en, this message translates to:
  /// **'Time format'**
  String get timeFormat;

  /// No description provided for @imoLIVEFollowsYourDevice.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE follows your device setting so timestamps stay '**
  String get imoLIVEFollowsYourDevice;

  /// No description provided for @pairingASecondDeviceIs.
  ///
  /// In en, this message translates to:
  /// **'Pairing a second device is not available yet. This screen '**
  String get pairingASecondDeviceIs;

  /// No description provided for @linkADevice.
  ///
  /// In en, this message translates to:
  /// **'Link a device'**
  String get linkADevice;

  /// No description provided for @openImoLIVEOnAnother.
  ///
  /// In en, this message translates to:
  /// **'Open Imo LIVE on another device and scan this code. '**
  String get openImoLIVEOnAnother;

  /// No description provided for @pairADevice.
  ///
  /// In en, this message translates to:
  /// **'Pair a device'**
  String get pairADevice;

  /// No description provided for @unlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get unlink;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @linkWithPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Link with phone number'**
  String get linkWithPhoneNumber;

  /// No description provided for @logOutOfAllDevices.
  ///
  /// In en, this message translates to:
  /// **'Log out of all devices'**
  String get logOutOfAllDevices;

  /// No description provided for @removeAllLinkedDevices.
  ///
  /// In en, this message translates to:
  /// **'Remove all linked devices?'**
  String get removeAllLinkedDevices;

  /// No description provided for @everyNonCurrentEntryIs.
  ///
  /// In en, this message translates to:
  /// **'Every non-current entry is deleted from this '**
  String get everyNonCurrentEntryIs;

  /// No description provided for @removeAll.
  ///
  /// In en, this message translates to:
  /// **'Remove all'**
  String get removeAll;

  /// No description provided for @builtInLists.
  ///
  /// In en, this message translates to:
  /// **'Built-in lists'**
  String get builtInLists;

  /// No description provided for @aListIsASaved.
  ///
  /// In en, this message translates to:
  /// **'A list is a saved filter over your chats. Tapping one applies '**
  String get aListIsASaved;

  /// No description provided for @customLists.
  ///
  /// In en, this message translates to:
  /// **'Custom lists'**
  String get customLists;

  /// No description provided for @theWorkListIsA.
  ///
  /// In en, this message translates to:
  /// **'The Work list is a flag stored on each chat, so it survives '**
  String get theWorkListIsA;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @pickAFilterAndApply.
  ///
  /// In en, this message translates to:
  /// **'Pick a filter and apply it to the Chats tab'**
  String get pickAFilterAndApply;

  /// No description provided for @showAllChats.
  ///
  /// In en, this message translates to:
  /// **'Show all chats'**
  String get showAllChats;

  /// No description provided for @clearTheActiveFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear the active filter'**
  String get clearTheActiveFilter;

  /// No description provided for @chatsInWork.
  ///
  /// In en, this message translates to:
  /// **'Chats in \"Work\"'**
  String get chatsInWork;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @directChat.
  ///
  /// In en, this message translates to:
  /// **'Direct chat'**
  String get directChat;

  /// No description provided for @pickTheChatsThisList.
  ///
  /// In en, this message translates to:
  /// **'Pick the chats this list will always show.'**
  String get pickTheChatsThisList;

  /// No description provided for @chatsYouStarred.
  ///
  /// In en, this message translates to:
  /// **'Chats you starred'**
  String get chatsYouStarred;

  /// No description provided for @groupsCommunities.
  ///
  /// In en, this message translates to:
  /// **'Groups & communities'**
  String get groupsCommunities;

  /// No description provided for @everyone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// No description provided for @noFiltering.
  ///
  /// In en, this message translates to:
  /// **'No filtering'**
  String get noFiltering;

  /// No description provided for @notificationsAreDeliveredLocallyBy.
  ///
  /// In en, this message translates to:
  /// **'Notifications are delivered locally by the OS. There is no '**
  String get notificationsAreDeliveredLocallyBy;

  /// No description provided for @messageNotifications.
  ///
  /// In en, this message translates to:
  /// **'Message notifications'**
  String get messageNotifications;

  /// No description provided for @showNotifications.
  ///
  /// In en, this message translates to:
  /// **'Show notifications'**
  String get showNotifications;

  /// No description provided for @masterSwitchForEveryMessage.
  ///
  /// In en, this message translates to:
  /// **'Master switch for every message alert'**
  String get masterSwitchForEveryMessage;

  /// No description provided for @vibrate.
  ///
  /// In en, this message translates to:
  /// **'Vibrate'**
  String get vibrate;

  /// No description provided for @popup.
  ///
  /// In en, this message translates to:
  /// **'Popup'**
  String get popup;

  /// No description provided for @showABannerWhileYou.
  ///
  /// In en, this message translates to:
  /// **'Show a banner while you are using another app'**
  String get showABannerWhileYou;

  /// No description provided for @inApp.
  ///
  /// In en, this message translates to:
  /// **'In-app'**
  String get inApp;

  /// No description provided for @inAppSounds.
  ///
  /// In en, this message translates to:
  /// **'In-app sounds'**
  String get inAppSounds;

  /// No description provided for @inAppVibration.
  ///
  /// In en, this message translates to:
  /// **'In-app vibration'**
  String get inAppVibration;

  /// No description provided for @tryItOut.
  ///
  /// In en, this message translates to:
  /// **'Try it out'**
  String get tryItOut;

  /// No description provided for @sendATestNotification.
  ///
  /// In en, this message translates to:
  /// **'Send a test notification'**
  String get sendATestNotification;

  /// No description provided for @postsALocalNotificationThrough.
  ///
  /// In en, this message translates to:
  /// **'Posts a local notification through the OS'**
  String get postsALocalNotificationThrough;

  /// No description provided for @resetNotificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset notification settings'**
  String get resetNotificationSettings;

  /// No description provided for @restoreEveryNotificationOptionTo.
  ///
  /// In en, this message translates to:
  /// **'Restore every notification option to its default'**
  String get restoreEveryNotificationOptionTo;

  /// No description provided for @theseSwitchesControlWhatImo.
  ///
  /// In en, this message translates to:
  /// **'These switches control what Imo LIVE stores and displays on '**
  String get theseSwitchesControlWhatImo;

  /// No description provided for @whoCanSeeMyPersonal.
  ///
  /// In en, this message translates to:
  /// **'Who can see my personal info'**
  String get whoCanSeeMyPersonal;

  /// No description provided for @changingLastSeenAlsoAffects.
  ///
  /// In en, this message translates to:
  /// **'Changing \"Last seen\" also affects read receipts in a backed '**
  String get changingLastSeenAlsoAffects;

  /// No description provided for @lastSeenAndOnline.
  ///
  /// In en, this message translates to:
  /// **'Last seen and online'**
  String get lastSeenAndOnline;

  /// No description provided for @whoCanCallMe.
  ///
  /// In en, this message translates to:
  /// **'Who can call me'**
  String get whoCanCallMe;

  /// No description provided for @silenceUnknownCallers.
  ///
  /// In en, this message translates to:
  /// **'Silence unknown callers'**
  String get silenceUnknownCallers;

  /// No description provided for @muteCallNotificationsFromPeople.
  ///
  /// In en, this message translates to:
  /// **'Mute call notifications from people you have not saved'**
  String get muteCallNotificationsFromPeople;

  /// No description provided for @appSecurity.
  ///
  /// In en, this message translates to:
  /// **'App security'**
  String get appSecurity;

  /// No description provided for @requireADeviceCredentialBefore.
  ///
  /// In en, this message translates to:
  /// **'Require a device credential before opening the app'**
  String get requireADeviceCredentialBefore;

  /// No description provided for @appLockEnabled.
  ///
  /// In en, this message translates to:
  /// **'App lock enabled'**
  String get appLockEnabled;

  /// No description provided for @imoLIVEWillAskFor.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE will ask for your device credential on next '**
  String get imoLIVEWillAskFor;

  /// No description provided for @liveLocation.
  ///
  /// In en, this message translates to:
  /// **'Live location'**
  String get liveLocation;

  /// No description provided for @allowSharingYourCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Allow sharing your current location inside chats. Location '**
  String get allowSharingYourCurrentLocation;

  /// No description provided for @advancedPrivacySettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced privacy settings'**
  String get advancedPrivacySettings;

  /// No description provided for @advancedPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Advanced privacy'**
  String get advancedPrivacy;

  /// No description provided for @imoLIVEDoesNotClaim.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE does not claim end-to-end encryption. Messages '**
  String get imoLIVEDoesNotClaim;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @resetPrivacySettings.
  ///
  /// In en, this message translates to:
  /// **'Reset privacy settings'**
  String get resetPrivacySettings;

  /// No description provided for @restoreEveryPrivacyOptionTo.
  ///
  /// In en, this message translates to:
  /// **'Restore every privacy option to its default'**
  String get restoreEveryPrivacyOptionTo;

  /// No description provided for @resetPrivacySettings2.
  ///
  /// In en, this message translates to:
  /// **'Reset privacy settings?'**
  String get resetPrivacySettings2;

  /// No description provided for @allPrivacyOptionsReturnTo.
  ///
  /// In en, this message translates to:
  /// **'All privacy options return to their defaults. Your '**
  String get allPrivacyOptionsReturnTo;

  /// No description provided for @onDevicePrivacyModelSyncs.
  ///
  /// In en, this message translates to:
  /// **'On-device privacy model · syncs via Cloud Firestore'**
  String get onDevicePrivacyModelSyncs;

  /// No description provided for @mediaStoredOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Media stored on this device'**
  String get mediaStoredOnThisDevice;

  /// No description provided for @deleteAllMediaFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete all media files'**
  String get deleteAllMediaFiles;

  /// No description provided for @removesEveryFileKeptIn.
  ///
  /// In en, this message translates to:
  /// **'Removes every file kept in the folders above'**
  String get removesEveryFileKeptIn;

  /// No description provided for @deleteAllMedia.
  ///
  /// In en, this message translates to:
  /// **'Delete all media?'**
  String get deleteAllMedia;

  /// No description provided for @deleteEverything.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get deleteEverything;

  /// No description provided for @muted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muted;

  /// No description provided for @noChannelSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'No channel subscriptions'**
  String get noChannelSubscriptions;

  /// No description provided for @followAChannelFromThe.
  ///
  /// In en, this message translates to:
  /// **'Follow a channel from the Updates tab and it will appear '**
  String get followAChannelFromThe;

  /// No description provided for @followedChannels.
  ///
  /// In en, this message translates to:
  /// **'Followed channels'**
  String get followedChannels;

  /// No description provided for @mutingAChannelKeepsIt.
  ///
  /// In en, this message translates to:
  /// **'Muting a channel keeps it in your list but silences its '**
  String get mutingAChannelKeepsIt;

  /// No description provided for @createOrJoinOneFrom.
  ///
  /// In en, this message translates to:
  /// **'Create or join one from the Communities tab'**
  String get createOrJoinOneFrom;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @findChannels.
  ///
  /// In en, this message translates to:
  /// **'Find channels'**
  String get findChannels;

  /// No description provided for @browsePublicChannelsByCategory.
  ///
  /// In en, this message translates to:
  /// **'Browse public channels by category'**
  String get browsePublicChannelsByCategory;

  /// No description provided for @createAChannelOfYour.
  ///
  /// In en, this message translates to:
  /// **'Create a channel of your own'**
  String get createAChannelOfYour;

  /// No description provided for @startACommunityWithAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Start a community with announcement groups'**
  String get startACommunityWithAnnouncement;

  /// No description provided for @notificationDefaults.
  ///
  /// In en, this message translates to:
  /// **'Notification defaults'**
  String get notificationDefaults;

  /// No description provided for @channelNotifications.
  ///
  /// In en, this message translates to:
  /// **'Channel notifications'**
  String get channelNotifications;

  /// No description provided for @lastRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Last refreshed'**
  String get lastRefreshed;

  /// No description provided for @chatWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Chat wallpaper'**
  String get chatWallpaper;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @chooseAWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Choose a wallpaper'**
  String get chooseAWallpaper;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @useAPhotoFromYour.
  ///
  /// In en, this message translates to:
  /// **'Use a photo from your device'**
  String get useAPhotoFromYour;

  /// No description provided for @captureANewWallpaperWith.
  ///
  /// In en, this message translates to:
  /// **'Capture a new wallpaper with the camera'**
  String get captureANewWallpaperWith;

  /// No description provided for @removeCustomWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Remove custom wallpaper'**
  String get removeCustomWallpaper;

  /// No description provided for @deleteTheFileAndReturn.
  ///
  /// In en, this message translates to:
  /// **'Delete the file and return to the default'**
  String get deleteTheFileAndReturn;

  /// No description provided for @removeWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Remove wallpaper?'**
  String get removeWallpaper;

  /// No description provided for @theCopiedImageFileIs.
  ///
  /// In en, this message translates to:
  /// **'The copied image file is deleted and the default '**
  String get theCopiedImageFileIs;

  /// No description provided for @clearChat2.
  ///
  /// In en, this message translates to:
  /// **'Clear chat?'**
  String get clearChat2;

  /// No description provided for @allMessagesInThisChat.
  ///
  /// In en, this message translates to:
  /// **'All messages in this chat will be deleted from this device. '**
  String get allMessagesInThisChat;

  /// No description provided for @thisConversationAndAllIts.
  ///
  /// In en, this message translates to:
  /// **'This conversation and all its messages will be removed from '**
  String get thisConversationAndAllIts;

  /// No description provided for @newUpdate.
  ///
  /// In en, this message translates to:
  /// **'New update'**
  String get newUpdate;

  /// No description provided for @playVideo.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playVideo;

  /// No description provided for @pauseVideo.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseVideo;

  /// No description provided for @rewind10.
  ///
  /// In en, this message translates to:
  /// **'Rewind 10 seconds'**
  String get rewind10;

  /// No description provided for @forward10.
  ///
  /// In en, this message translates to:
  /// **'Forward 10 seconds'**
  String get forward10;

  /// No description provided for @textStatus.
  ///
  /// In en, this message translates to:
  /// **'Text status'**
  String get textStatus;

  /// No description provided for @photoOrVideo.
  ///
  /// In en, this message translates to:
  /// **'Photo or video'**
  String get photoOrVideo;

  /// No description provided for @typeAStatus.
  ///
  /// In en, this message translates to:
  /// **'Type a status'**
  String get typeAStatus;

  /// No description provided for @addAPhotoOrVideo.
  ///
  /// In en, this message translates to:
  /// **'Add a photo or video'**
  String get addAPhotoOrVideo;

  /// No description provided for @pickMediaFromYourGallery.
  ///
  /// In en, this message translates to:
  /// **'Pick media from your gallery to use as a status update.'**
  String get pickMediaFromYourGallery;

  /// No description provided for @chooseMedia.
  ///
  /// In en, this message translates to:
  /// **'Choose media'**
  String get chooseMedia;

  /// No description provided for @videoStatus.
  ///
  /// In en, this message translates to:
  /// **'Video status'**
  String get videoStatus;

  /// No description provided for @smallerText.
  ///
  /// In en, this message translates to:
  /// **'Smaller text'**
  String get smallerText;

  /// No description provided for @aa.
  ///
  /// In en, this message translates to:
  /// **'Aa'**
  String get aa;

  /// No description provided for @largerText.
  ///
  /// In en, this message translates to:
  /// **'Larger text'**
  String get largerText;

  /// No description provided for @thisMediaFileIsNo.
  ///
  /// In en, this message translates to:
  /// **'This media file is no longer available.'**
  String get thisMediaFileIsNo;

  /// No description provided for @deleteUpdate.
  ///
  /// In en, this message translates to:
  /// **'Delete update?'**
  String get deleteUpdate;

  /// No description provided for @thisUpdateIsRemovedFor.
  ///
  /// In en, this message translates to:
  /// **'This update is removed for everyone immediately.'**
  String get thisUpdateIsRemovedFor;

  /// No description provided for @sendAMessage.
  ///
  /// In en, this message translates to:
  /// **'Send a message…'**
  String get sendAMessage;

  /// No description provided for @statusPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Status privacy'**
  String get statusPrivacy;

  /// No description provided for @theRestOfTheApp.
  ///
  /// In en, this message translates to:
  /// **'The rest of the app keeps working. Go back and try again.'**
  String get theRestOfTheApp;

  /// No description provided for @goToChats.
  ///
  /// In en, this message translates to:
  /// **'Go to Chats'**
  String get goToChats;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @byContinuingYouAgreeTo.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to the Imo LIVE Terms and Privacy Policy.'**
  String get byContinuingYouAgreeTo;

  /// No description provided for @aboutAShortLineAbout.
  ///
  /// In en, this message translates to:
  /// **'About — a short line about you'**
  String get aboutAShortLineAbout;

  /// No description provided for @age.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get age;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @scheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduled;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @minimise.
  ///
  /// In en, this message translates to:
  /// **'Minimise'**
  String get minimise;

  /// No description provided for @flipCamera.
  ///
  /// In en, this message translates to:
  /// **'Flip camera'**
  String get flipCamera;

  /// No description provided for @noContactsYet.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get noContactsYet;

  /// No description provided for @addContactsThenStarThe.
  ///
  /// In en, this message translates to:
  /// **'Add contacts, then star the people you call most to '**
  String get addContactsThenStarThe;

  /// No description provided for @noFavouritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favourites yet'**
  String get noFavouritesYet;

  /// No description provided for @tapEditAndStarThe.
  ///
  /// In en, this message translates to:
  /// **'Tap Edit and star the contacts you call most '**
  String get tapEditAndStarThe;

  /// No description provided for @otherContacts.
  ///
  /// In en, this message translates to:
  /// **'Other contacts'**
  String get otherContacts;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @anythingToRemember.
  ///
  /// In en, this message translates to:
  /// **'Anything to remember?'**
  String get anythingToRemember;

  /// No description provided for @saveReminder.
  ///
  /// In en, this message translates to:
  /// **'Save reminder'**
  String get saveReminder;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get removeAttachment;

  /// No description provided for @attachAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Attach a photo'**
  String get attachAPhoto;

  /// No description provided for @attachAVideo.
  ///
  /// In en, this message translates to:
  /// **'Attach a video'**
  String get attachAVideo;

  /// No description provided for @attachAFile.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get attachAFile;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @discovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get discovery;

  /// No description provided for @publicChannel.
  ///
  /// In en, this message translates to:
  /// **'Public channel'**
  String get publicChannel;

  /// No description provided for @changesAreWrittenToFirestore.
  ///
  /// In en, this message translates to:
  /// **'Changes are written to Firestore immediately. Followers see them '**
  String get changesAreWrittenToFirestore;

  /// No description provided for @whatDoesThisChannelPost.
  ///
  /// In en, this message translates to:
  /// **'What does this channel post about?'**
  String get whatDoesThisChannelPost;

  /// No description provided for @visibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get visibility;

  /// No description provided for @a12CharacterSecretKey.
  ///
  /// In en, this message translates to:
  /// **'A 12-character secret key is generated when you '**
  String get a12CharacterSecretKey;

  /// No description provided for @deletePost.
  ///
  /// In en, this message translates to:
  /// **'Delete post'**
  String get deletePost;

  /// No description provided for @tapToPlay.
  ///
  /// In en, this message translates to:
  /// **'Tap to play'**
  String get tapToPlay;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @docs.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get docs;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @polls.
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get polls;

  /// No description provided for @events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// No description provided for @fromThem.
  ///
  /// In en, this message translates to:
  /// **'From them'**
  String get fromThem;

  /// No description provided for @thisMessageIsQueuedOn.
  ///
  /// In en, this message translates to:
  /// **'This message is queued on your device and has not '**
  String get thisMessageIsQueuedOn;

  /// No description provided for @starts.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get starts;

  /// No description provided for @ends.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get ends;

  /// No description provided for @locationOptional.
  ///
  /// In en, this message translates to:
  /// **'Location (optional)'**
  String get locationOptional;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @shareAContact.
  ///
  /// In en, this message translates to:
  /// **'Share a contact'**
  String get shareAContact;

  /// No description provided for @noContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts'**
  String get noContacts;

  /// No description provided for @addAContactFirstTo.
  ///
  /// In en, this message translates to:
  /// **'Add a contact first to share it in a chat.'**
  String get addAContactFirstTo;

  /// No description provided for @deleteForEveryone2.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone?'**
  String get deleteForEveryone2;

  /// No description provided for @theMessageIsRemovedFrom.
  ///
  /// In en, this message translates to:
  /// **'The message is removed from this device and replaced with a \"deleted\" '**
  String get theMessageIsRemovedFrom;

  /// No description provided for @photoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Photo unavailable'**
  String get photoUnavailable;

  /// No description provided for @cancelReply.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get cancelReply;

  /// No description provided for @announcements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcements;

  /// No description provided for @everyoneInTheCommunityReceives.
  ///
  /// In en, this message translates to:
  /// **'Everyone in the community receives announcement messages. '**
  String get everyoneInTheCommunityReceives;

  /// No description provided for @openAnnouncementChat.
  ///
  /// In en, this message translates to:
  /// **'Open announcement chat'**
  String get openAnnouncementChat;

  /// No description provided for @everyoneYouAddBecomesA.
  ///
  /// In en, this message translates to:
  /// **'Everyone you add becomes a member of the announcement group. '**
  String get everyoneYouAddBecomesA;

  /// No description provided for @pickPeopleFromYourContacts.
  ///
  /// In en, this message translates to:
  /// **'Pick people from your contacts'**
  String get pickPeopleFromYourContacts;

  /// No description provided for @adminOnlyAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Admin-only announcements'**
  String get adminOnlyAnnouncements;

  /// No description provided for @onlyYouAndOtherAdmins.
  ///
  /// In en, this message translates to:
  /// **'Only you and other admins can post announcements'**
  String get onlyYouAndOtherAdmins;

  /// No description provided for @communitiesLiveOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Communities live on this device. Invite links are generated '**
  String get communitiesLiveOnThisDevice;

  /// No description provided for @noMatchingCountry.
  ///
  /// In en, this message translates to:
  /// **'No matching country'**
  String get noMatchingCountry;

  /// No description provided for @tryADifferentNameOr2.
  ///
  /// In en, this message translates to:
  /// **'Try a different name or dialling code.'**
  String get tryADifferentNameOr2;

  /// No description provided for @optionalHandle.
  ///
  /// In en, this message translates to:
  /// **'Optional handle'**
  String get optionalHandle;

  /// No description provided for @heyThereIAmUsing.
  ///
  /// In en, this message translates to:
  /// **'Hey there! I am using Imo LIVE.'**
  String get heyThereIAmUsing;

  /// No description provided for @saveToDeviceContacts.
  ///
  /// In en, this message translates to:
  /// **'Save to device contacts'**
  String get saveToDeviceContacts;

  /// No description provided for @searchNameOrNumber.
  ///
  /// In en, this message translates to:
  /// **'Search name or number'**
  String get searchNameOrNumber;

  /// No description provided for @checkingImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'Checking Imo LIVE…'**
  String get checkingImoLIVE;

  /// No description provided for @couldNotReachImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Imo LIVE. The number is saved locally.'**
  String get couldNotReachImoLIVE;

  /// No description provided for @thisUserIsOnImo.
  ///
  /// In en, this message translates to:
  /// **'This user is on Imo LIVE'**
  String get thisUserIsOnImo;

  /// No description provided for @groupNAME.
  ///
  /// In en, this message translates to:
  /// **'GROUP NAME'**
  String get groupNAME;

  /// No description provided for @description2.
  ///
  /// In en, this message translates to:
  /// **'DESCRIPTION'**
  String get description2;

  /// No description provided for @mode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// No description provided for @capabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get capabilities;

  /// No description provided for @theseAreTheBoundariesOf.
  ///
  /// In en, this message translates to:
  /// **'These are the boundaries of this build. Each one is honest '**
  String get theseAreTheBoundariesOf;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @emailGoogleAndFacebookSign.
  ///
  /// In en, this message translates to:
  /// **'Email, Google and phone sign-in, profile and people '**
  String get emailGoogleAndFacebookSign;

  /// No description provided for @worksOffline.
  ///
  /// In en, this message translates to:
  /// **'Works offline'**
  String get worksOffline;

  /// No description provided for @chatsMessagesMediaVoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'Chats, messages, media, voice notes, polls, events, '**
  String get chatsMessagesMediaVoiceNotes;

  /// No description provided for @needsConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Needs configuration'**
  String get needsConfiguration;

  /// No description provided for @cloudflareR2CredentialsTheFacebook.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare R2 credentials, push '**
  String get cloudflareR2CredentialsTheFacebook;

  /// No description provided for @whereToNext.
  ///
  /// In en, this message translates to:
  /// **'Where to next'**
  String get whereToNext;

  /// No description provided for @helpFAQ.
  ///
  /// In en, this message translates to:
  /// **'Help & FAQ'**
  String get helpFAQ;

  /// No description provided for @licences.
  ///
  /// In en, this message translates to:
  /// **'Licences'**
  String get licences;

  /// No description provided for @madeWithFlutter.
  ///
  /// In en, this message translates to:
  /// **'Made with Flutter'**
  String get madeWithFlutter;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get contactUs;

  /// No description provided for @theseActionsHandOffTo.
  ///
  /// In en, this message translates to:
  /// **'These actions hand off to your own apps — nothing is sent by '**
  String get theseActionsHandOffTo;

  /// No description provided for @emailSupport.
  ///
  /// In en, this message translates to:
  /// **'Email support'**
  String get emailSupport;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo?'**
  String get removePhoto;

  /// No description provided for @yourProfilePhotoIsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your profile photo is deleted from this device.'**
  String get yourProfilePhotoIsDeleted;

  /// No description provided for @yourNameAboutTextAnd.
  ///
  /// In en, this message translates to:
  /// **'Your name, about text and photo are saved on this device and '**
  String get yourNameAboutTextAnd;

  /// No description provided for @myDetails.
  ///
  /// In en, this message translates to:
  /// **'My details'**
  String get myDetails;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @myActivity.
  ///
  /// In en, this message translates to:
  /// **'My activity'**
  String get myActivity;

  /// No description provided for @sharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get sharing;

  /// No description provided for @shareMyQRCode.
  ///
  /// In en, this message translates to:
  /// **'Share my QR code'**
  String get shareMyQRCode;

  /// No description provided for @letSomeoneScanToAdd.
  ///
  /// In en, this message translates to:
  /// **'Let someone scan to add you'**
  String get letSomeoneScanToAdd;

  /// No description provided for @shareMyContactCard.
  ///
  /// In en, this message translates to:
  /// **'Share my contact card'**
  String get shareMyContactCard;

  /// No description provided for @sendYourNameAndNumber.
  ///
  /// In en, this message translates to:
  /// **'Send your name and number'**
  String get sendYourNameAndNumber;

  /// No description provided for @resultsComeLiveFromImo.
  ///
  /// In en, this message translates to:
  /// **'Results come live from Imo LIVE. People who have not '**
  String get resultsComeLiveFromImo;

  /// No description provided for @signOut2.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOut2;

  /// No description provided for @yourChatsStayOnThis.
  ///
  /// In en, this message translates to:
  /// **'Your chats stay on this device, but they stop '**
  String get yourChatsStayOnThis;

  /// No description provided for @twoStepVerificationAndEnd.
  ///
  /// In en, this message translates to:
  /// **'Two-step verification and end-to-end encryption require a '**
  String get twoStepVerificationAndEnd;

  /// No description provided for @requireADeviceCredentialTo.
  ///
  /// In en, this message translates to:
  /// **'Require a device credential to open Imo LIVE'**
  String get requireADeviceCredentialTo;

  /// No description provided for @accentColour.
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get accentColour;

  /// No description provided for @a.
  ///
  /// In en, this message translates to:
  /// **'A'**
  String get a;

  /// No description provided for @thisIsHowYourMessages.
  ///
  /// In en, this message translates to:
  /// **'This is how your messages will look at '**
  String get thisIsHowYourMessages;

  /// No description provided for @resetTextSize.
  ///
  /// In en, this message translates to:
  /// **'Reset text size'**
  String get resetTextSize;

  /// No description provided for @chatTheme.
  ///
  /// In en, this message translates to:
  /// **'Chat theme'**
  String get chatTheme;

  /// No description provided for @appIcon.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get appIcon;

  /// No description provided for @changingTheLauncherIconIs.
  ///
  /// In en, this message translates to:
  /// **'Changing the launcher icon is a platform action. The choice is '**
  String get changingTheLauncherIconIs;

  /// No description provided for @thisContactWillBeAble.
  ///
  /// In en, this message translates to:
  /// **'This contact will be able to reach you again '**
  String get thisContactWillBeAble;

  /// No description provided for @small.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get small;

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @large.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get large;

  /// No description provided for @extraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra large'**
  String get extraLarge;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @unlinkingRemovesADeviceFrom.
  ///
  /// In en, this message translates to:
  /// **'Unlinking removes a device from this list. Because pairing '**
  String get unlinkingRemovesADeviceFrom;

  /// No description provided for @theDeviceIsRemovedFrom.
  ///
  /// In en, this message translates to:
  /// **'The device is removed from this local '**
  String get theDeviceIsRemovedFrom;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @keepMessagesForever.
  ///
  /// In en, this message translates to:
  /// **'Keep messages forever'**
  String get keepMessagesForever;

  /// No description provided for @s24Hours.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get s24Hours;

  /// No description provided for @s7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get s7Days;

  /// No description provided for @s90Days.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get s90Days;

  /// No description provided for @chatSettings.
  ///
  /// In en, this message translates to:
  /// **'Chat settings'**
  String get chatSettings;

  /// No description provided for @notificationsStorage.
  ///
  /// In en, this message translates to:
  /// **'Notifications & storage'**
  String get notificationsStorage;

  /// No description provided for @appExperience.
  ///
  /// In en, this message translates to:
  /// **'App experience'**
  String get appExperience;

  /// No description provided for @theSwitchMatchesTheSystem.
  ///
  /// In en, this message translates to:
  /// **'The switch matches the system while \"System\" is selected. '**
  String get theSwitchMatchesTheSystem;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeMode;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @reviewer.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get reviewer;

  /// No description provided for @fromImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'from Imo LIVE'**
  String get fromImoLIVE;

  /// No description provided for @nothingStoredYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing stored yet'**
  String get nothingStoredYet;

  /// No description provided for @photosVideosVoiceNotesAnd.
  ///
  /// In en, this message translates to:
  /// **'Photos, videos, voice notes and documents you send or '**
  String get photosVideosVoiceNotesAnd;

  /// No description provided for @breakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get breakdown;

  /// No description provided for @messageData.
  ///
  /// In en, this message translates to:
  /// **'Message data'**
  String get messageData;

  /// No description provided for @purgeExpiredMessages.
  ///
  /// In en, this message translates to:
  /// **'Purge expired messages'**
  String get purgeExpiredMessages;

  /// No description provided for @removesMessagesWhoseDisappearingTimer.
  ///
  /// In en, this message translates to:
  /// **'Removes messages whose disappearing timer already '**
  String get removesMessagesWhoseDisappearingTimer;

  /// No description provided for @addACaption.
  ///
  /// In en, this message translates to:
  /// **'Add a caption…'**
  String get addACaption;

  /// No description provided for @deleteUpdate2.
  ///
  /// In en, this message translates to:
  /// **'Delete update'**
  String get deleteUpdate2;

  /// No description provided for @reply2.
  ///
  /// In en, this message translates to:
  /// **'Reply…'**
  String get reply2;

  /// No description provided for @shareATextPhotoOr.
  ///
  /// In en, this message translates to:
  /// **'Share a text, photo or video update. It disappears '**
  String get shareATextPhotoOr;

  /// No description provided for @updatesAreStoredOnThis.
  ///
  /// In en, this message translates to:
  /// **'Updates are stored on this device only. Expiry after 24 '**
  String get updatesAreStoredOnThis;

  /// No description provided for @followBroadcastChannelsYouSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Follow broadcast channels you subscribe to'**
  String get followBroadcastChannelsYouSubscribe;

  /// No description provided for @createAChannel.
  ///
  /// In en, this message translates to:
  /// **'Create a channel'**
  String get createAChannel;

  /// No description provided for @broadcastToFollowersWithoutA.
  ///
  /// In en, this message translates to:
  /// **'Broadcast to followers without a group'**
  String get broadcastToFollowersWithoutA;

  /// No description provided for @groupNotifications.
  ///
  /// In en, this message translates to:
  /// **'Group notifications'**
  String get groupNotifications;

  /// No description provided for @showPreview.
  ///
  /// In en, this message translates to:
  /// **'Show preview'**
  String get showPreview;

  /// No description provided for @includeMessageTextInThe.
  ///
  /// In en, this message translates to:
  /// **'Include message text in the notification'**
  String get includeMessageTextInThe;

  /// No description provided for @notifyWhenSomeoneReactsTo.
  ///
  /// In en, this message translates to:
  /// **'Notify when someone reacts to your message'**
  String get notifyWhenSomeoneReactsTo;

  /// No description provided for @callsStatus.
  ///
  /// In en, this message translates to:
  /// **'Calls & status'**
  String get callsStatus;

  /// No description provided for @callNotifications.
  ///
  /// In en, this message translates to:
  /// **'Call notifications'**
  String get callNotifications;

  /// No description provided for @statusNotifications.
  ///
  /// In en, this message translates to:
  /// **'Status notifications'**
  String get statusNotifications;

  /// No description provided for @soundVibration.
  ///
  /// In en, this message translates to:
  /// **'Sound & vibration'**
  String get soundVibration;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @notificationTone.
  ///
  /// In en, this message translates to:
  /// **'Notification tone'**
  String get notificationTone;

  /// No description provided for @profilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profilePhoto;

  /// No description provided for @messaging.
  ///
  /// In en, this message translates to:
  /// **'Messaging'**
  String get messaging;

  /// No description provided for @readReceipts.
  ///
  /// In en, this message translates to:
  /// **'Read receipts'**
  String get readReceipts;

  /// No description provided for @sendDeliveryAndReadTicks.
  ///
  /// In en, this message translates to:
  /// **'Send delivery and read ticks. Turning this off stops the '**
  String get sendDeliveryAndReadTicks;

  /// No description provided for @whoCanAddMeTo.
  ///
  /// In en, this message translates to:
  /// **'Who can add me to groups'**
  String get whoCanAddMeTo;

  /// No description provided for @defaultMessageTimer.
  ///
  /// In en, this message translates to:
  /// **'Default message timer'**
  String get defaultMessageTimer;

  /// No description provided for @pickAnExistingPhotoOr.
  ///
  /// In en, this message translates to:
  /// **'Pick an existing photo or video'**
  String get pickAnExistingPhotoOr;

  /// No description provided for @openTheLinkInThe2.
  ///
  /// In en, this message translates to:
  /// **'Open the link in the email to confirm this address. This screen finishes on its own.'**
  String get openTheLinkInThe2;

  /// No description provided for @everyCallEntryOnThis2.
  ///
  /// In en, this message translates to:
  /// **'Every call entry on this device is deleted. Contacts and scheduled calls are kept.'**
  String get everyCallEntryOnThis2;

  /// No description provided for @addContactsThenStarThe2.
  ///
  /// In en, this message translates to:
  /// **'Add contacts, then star the people you call most to reach them from here.'**
  String get addContactsThenStarThe2;

  /// No description provided for @tapEditAndStarThe2.
  ///
  /// In en, this message translates to:
  /// **'Tap Edit and star the contacts you call most often. They appear here for quick dialling.'**
  String get tapEditAndStarThe2;

  /// No description provided for @remindersFireFromTheLocal2.
  ///
  /// In en, this message translates to:
  /// **'Reminders fire from the local notification plugin. They are not invitations — the other person is not notified.'**
  String get remindersFireFromTheLocal2;

  /// No description provided for @shareTheSecretKeyWith2.
  ///
  /// In en, this message translates to:
  /// **'Share the secret key with the people you want to let in. Their requests will appear here.'**
  String get shareTheSecretKeyWith2;

  /// No description provided for @itIsNotOnThis2.
  ///
  /// In en, this message translates to:
  /// **'It is not on this device and could not be loaded from the server. Check your connection and try again.'**
  String get itIsNotOnThis2;

  /// No description provided for @postsAreOnlyVisibleTo2.
  ///
  /// In en, this message translates to:
  /// **'Posts are only visible to members. Send a request and the owner will decide whether to let you in.'**
  String get postsAreOnlyVisibleTo2;

  /// No description provided for @thisChannelIsReservedFor2.
  ///
  /// In en, this message translates to:
  /// **'This channel is reserved for premium members. Earn points by watching ads, then redeem them for premium to read it.'**
  String get thisChannelIsReservedFor2;

  /// No description provided for @yourChannelMeetsTheRequirements2.
  ///
  /// In en, this message translates to:
  /// **'Your channel meets the requirements. A reviewer will check it and you will be notified of the decision.'**
  String get yourChannelMeetsTheRequirements2;

  /// No description provided for @premiumOnly.
  ///
  /// In en, this message translates to:
  /// **'Premium only'**
  String get premiumOnly;

  /// No description provided for @coverImage.
  ///
  /// In en, this message translates to:
  /// **'Cover image'**
  String get coverImage;

  /// No description provided for @tapToCopyThisIs.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy — this is the only time it is shown'**
  String get tapToCopyThisIs;

  /// No description provided for @changesAreWrittenToFirestore2.
  ///
  /// In en, this message translates to:
  /// **'Changes are written to Firestore immediately. Followers see them on their next sync.'**
  String get changesAreWrittenToFirestore2;

  /// No description provided for @everyoneCurrentlyUsingTheOld2.
  ///
  /// In en, this message translates to:
  /// **'Everyone currently using the old key keeps their access, but the old key can no longer be used to request a join.'**
  String get everyoneCurrentlyUsingTheOld2;

  /// No description provided for @aReviewerWillCheckThat2.
  ///
  /// In en, this message translates to:
  /// **'A reviewer will check that your channel meets the audience and engagement requirements.'**
  String get aReviewerWillCheckThat2;

  /// No description provided for @channelsAppearHereOnceThey2.
  ///
  /// In en, this message translates to:
  /// **'Channels appear here once they pass the follower and reaction thresholds and apply.'**
  String get channelsAppearHereOnceThey2;

  /// No description provided for @a12CharacterSecretKey2.
  ///
  /// In en, this message translates to:
  /// **'A 12-character secret key is generated when you create the channel. You will see it once — share it with the people you want to let in.'**
  String get a12CharacterSecretKey2;

  /// No description provided for @archivedChatsAreHiddenFrom2.
  ///
  /// In en, this message translates to:
  /// **'Archived chats are hidden from the main list but keep all their messages. Swipe a chat and choose Archive to move it here.'**
  String get archivedChatsAreHiddenFrom2;

  /// No description provided for @aBroadcastSendsAnIndividual2.
  ///
  /// In en, this message translates to:
  /// **'A broadcast sends an individual copy of your message to each recipient. Replies arrive as normal one-to-one chats.'**
  String get aBroadcastSendsAnIndividual2;

  /// No description provided for @createAListOfUp2.
  ///
  /// In en, this message translates to:
  /// **'Create a list of up to 256 recipients and message them all at once. Each person receives a private copy.'**
  String get createAListOfUp2;

  /// No description provided for @theListIsDeletedExisting2.
  ///
  /// In en, this message translates to:
  /// **'The list is deleted. Existing conversations with its recipients are kept.'**
  String get theListIsDeletedExisting2;

  /// No description provided for @localStorageCouldNotBe2.
  ///
  /// In en, this message translates to:
  /// **'Local storage could not be opened, so your chats, contacts and settings are not being saved. Messages will be lost when the app closes.'**
  String get localStorageCouldNotBe2;

  /// No description provided for @fromMe.
  ///
  /// In en, this message translates to:
  /// **'From me'**
  String get fromMe;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @thisMessageIsQueuedOn2.
  ///
  /// In en, this message translates to:
  /// **'This message is queued on your device and has not been sent yet. It will go out on its own as soon as you are back online.'**
  String get thisMessageIsQueuedOn2;

  /// No description provided for @allMessagesInThisConversation2.
  ///
  /// In en, this message translates to:
  /// **'All messages in this conversation will be removed from this device. This cannot be undone.'**
  String get allMessagesInThisConversation2;

  /// No description provided for @aCommunityGroupsRelatedChats2.
  ///
  /// In en, this message translates to:
  /// **'A community groups related chats under one announcement channel. Create one to organise a club, a class or a neighbourhood.'**
  String get aCommunityGroupsRelatedChats2;

  /// No description provided for @theCommunityAndItsAnnouncement2.
  ///
  /// In en, this message translates to:
  /// **'The community and its announcement group are removed from this device. Member chats are kept.'**
  String get theCommunityAndItsAnnouncement2;

  /// No description provided for @channelsBroadcastOneWayTo2.
  ///
  /// In en, this message translates to:
  /// **'Channels broadcast one-way to followers. Create one, or follow a channel to see its updates here.'**
  String get channelsBroadcastOneWayTo2;

  /// No description provided for @everyoneInTheCommunityReceives2.
  ///
  /// In en, this message translates to:
  /// **'Everyone in the community receives announcement messages. Only admins can post.'**
  String get everyoneInTheCommunityReceives2;

  /// No description provided for @theCommunityIsRemovedFrom2.
  ///
  /// In en, this message translates to:
  /// **'The community is removed from this device. Groups inside it stay as normal groups.'**
  String get theCommunityIsRemovedFrom2;

  /// No description provided for @everyoneYouAddBecomesA2.
  ///
  /// In en, this message translates to:
  /// **'Everyone you add becomes a member of the announcement group. You can add more people later.'**
  String get everyoneYouAddBecomesA2;

  /// No description provided for @communitiesLiveOnThisDevice2.
  ///
  /// In en, this message translates to:
  /// **'Communities live on this device. Invite links are generated locally, so another person cannot open them yet.'**
  String get communitiesLiveOnThisDevice2;

  /// No description provided for @thisPersonIsNotIn2.
  ///
  /// In en, this message translates to:
  /// **'This person is not in your contacts and has no Imo LIVE account, so there is no profile to show.'**
  String get thisPersonIsNotIn2;

  /// No description provided for @mediaAttachesToConversationsOpen2.
  ///
  /// In en, this message translates to:
  /// **'Media attaches to conversations. Open the chat and use the search icon to filter photos, videos, links and documents for this person.'**
  String get mediaAttachesToConversationsOpen2;

  /// No description provided for @openTheChatAndChoose2.
  ///
  /// In en, this message translates to:
  /// **'Open the chat and choose Disappearing messages from the menu to change this setting. It applies to new messages only.'**
  String get openTheChatAndChoose2;

  /// No description provided for @theContactIsRemovedFrom2.
  ///
  /// In en, this message translates to:
  /// **'The contact is removed from your list. Existing chats stay in place.'**
  String get theContactIsRemovedFrom2;

  /// No description provided for @importNamesAndNumbersFrom.
  ///
  /// In en, this message translates to:
  /// **'Import names and numbers from your address book'**
  String get importNamesAndNumbersFrom;

  /// No description provided for @imoLIVECouldNotRead2.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE could not read your device contacts. Grant the contacts permission in your system settings and try again.'**
  String get imoLIVECouldNotRead2;

  /// No description provided for @newMessagesInThisChat2.
  ///
  /// In en, this message translates to:
  /// **'New messages in this chat will disappear after the selected time. Messages sent before the change keep their original timer.'**
  String get newMessagesInThisChat2;

  /// No description provided for @openTheConversationAndTap2.
  ///
  /// In en, this message translates to:
  /// **'Open the conversation and tap the search icon to filter media, links and documents shared in this group.'**
  String get openTheConversationAndTap2;

  /// No description provided for @theInviteCodeIsGenerated2.
  ///
  /// In en, this message translates to:
  /// **'The invite code is generated locally. Joining via a link needs a server to resolve the code into a group.'**
  String get theInviteCodeIsGenerated2;

  /// No description provided for @invalidatingAnInviteLinkIs2.
  ///
  /// In en, this message translates to:
  /// **'Invalidating an invite link is a server action — old codes must stop resolving globally. Locally a new code can be generated but the old one keeps working.'**
  String get invalidatingAnInviteLinkIs2;

  /// No description provided for @youLeaveTheGroupYour2.
  ///
  /// In en, this message translates to:
  /// **'You leave the group. Your existing messages stay in the conversation unless you delete it.'**
  String get youLeaveTheGroupYour2;

  /// No description provided for @theGroupItsMembersAnd2.
  ///
  /// In en, this message translates to:
  /// **'The group, its members and every message are permanently deleted from this device.'**
  String get theGroupItsMembersAnd2;

  /// No description provided for @aGroupNeedsAtLeast2.
  ///
  /// In en, this message translates to:
  /// **'A group needs at least one other person. You will be added as the creator and first admin.'**
  String get aGroupNeedsAtLeast2;

  /// No description provided for @adminsCanAddOrRemove2.
  ///
  /// In en, this message translates to:
  /// **'Admins can add or remove members, edit the group photo, name and description, and delete messages. Members can send messages and share media.'**
  String get adminsCanAddOrRemove2;

  /// No description provided for @imoLIVESyncsThroughFirebase2.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE syncs through Firebase — Authentication and Cloud Firestore — and stores media in Cloudflare R2. An on-device copy keeps every screen working without a connection.'**
  String get imoLIVESyncsThroughFirebase2;

  /// No description provided for @theseAreTheBoundariesOf2.
  ///
  /// In en, this message translates to:
  /// **'These are the boundaries of this build. Each one is honest about what works today versus what still needs configuring.'**
  String get theseAreTheBoundariesOf2;

  /// No description provided for @emailGoogleAndFacebookSign2.
  ///
  /// In en, this message translates to:
  /// **'Email, Google and phone sign-in, profile and people directory, real-time chat and message sync, and media upload through Cloudflare R2'**
  String get emailGoogleAndFacebookSign2;

  /// No description provided for @chatsMessagesMediaVoiceNotes2.
  ///
  /// In en, this message translates to:
  /// **'Chats, messages, media, voice notes, polls, events, location shares, statuses, channels, communities, calls UI, settings and localisation'**
  String get chatsMessagesMediaVoiceNotes2;

  /// No description provided for @cloudflareR2CredentialsTheFacebook2.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare R2 credentials, push delivery, device pairing and end-to-end encryption'**
  String get cloudflareR2CredentialsTheFacebook2;

  /// No description provided for @everyScreenDependsOnAn2.
  ///
  /// In en, this message translates to:
  /// **'Every screen depends on an abstract repository interface. Chats and messages are read from the Hive cache and mirrored from Cloud Firestore, and media goes to Cloudflare R2 through the same MediaRepository interface — so no screen talks to the network directly.'**
  String get everyScreenDependsOnAn2;

  /// No description provided for @everythingBelowAlreadyHasIts2.
  ///
  /// In en, this message translates to:
  /// **'Everything below already has its interface and local implementation in place, so wiring it up is additive — no screen has to change.'**
  String get everythingBelowAlreadyHasIts2;

  /// No description provided for @theseActionsHandOffTo2.
  ///
  /// In en, this message translates to:
  /// **'These actions hand off to your own apps — nothing is sent by Imo LIVE itself.'**
  String get theseActionsHandOffTo2;

  /// No description provided for @openTheWebsite.
  ///
  /// In en, this message translates to:
  /// **'Open the website'**
  String get openTheWebsite;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @locallyStoredCountsAndStorage.
  ///
  /// In en, this message translates to:
  /// **'Locally stored counts and storage usage'**
  String get locallyStoredCountsAndStorage;

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legal;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @imoLIVECollectsNoAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE collects no analytics. Your profile, chats and messages are stored on this device and synchronised to Cloud Firestore under your account; media is uploaded to Cloudflare R2 so the recipient can fetch it. Deleting the app removes the on-device copy but not your account data — clear that from Account settings first.'**
  String get imoLIVECollectsNoAnalytics;

  /// No description provided for @theCodeCarriesAnImo2.
  ///
  /// In en, this message translates to:
  /// **'The code carries an Imo LIVE identifier. Another person can look your user id up in Search, but scanning a code from inside the app is not supported yet.'**
  String get theCodeCarriesAnImo2;

  /// No description provided for @optionalHandleOthersCanSearch.
  ///
  /// In en, this message translates to:
  /// **'Optional handle others can search for'**
  String get optionalHandleOthersCanSearch;

  /// No description provided for @yourNameAboutTextAnd2.
  ///
  /// In en, this message translates to:
  /// **'Your name, about text and photo are saved on this device and published to your Imo LIVE account so contacts can find you. Edit them freely — nothing is shared beyond your profile.'**
  String get yourNameAboutTextAnd2;

  /// No description provided for @resultsComeLiveFromImo2.
  ///
  /// In en, this message translates to:
  /// **'Results come live from Imo LIVE. People who have not joined yet can be invited from the contact screen.'**
  String get resultsComeLiveFromImo2;

  /// No description provided for @imoLIVECouldNotBe2.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE could not be reached. Check your connection and try again.'**
  String get imoLIVECouldNotBe2;

  /// No description provided for @inviteThemToImoLIVE2.
  ///
  /// In en, this message translates to:
  /// **'Invite them to Imo LIVE and you can start chatting as soon as they join.'**
  String get inviteThemToImoLIVE2;

  /// No description provided for @yourChatsStayOnThis2.
  ///
  /// In en, this message translates to:
  /// **'Your chats stay on this device, but they stop syncing until you sign back in.'**
  String get yourChatsStayOnThis2;

  /// No description provided for @twoStepVerificationAndEnd2.
  ///
  /// In en, this message translates to:
  /// **'Two-step verification and end-to-end encryption require a server and key-exchange layer, which is not part of this local build. Nothing here pretends those protections are active.'**
  String get twoStepVerificationAndEnd2;

  /// No description provided for @deletesChatsMessagesContactsStatuses2.
  ///
  /// In en, this message translates to:
  /// **'Deletes chats, messages, contacts, statuses and settings from this device'**
  String get deletesChatsMessagesContactsStatuses2;

  /// No description provided for @everyChatMessageContactAnd2.
  ///
  /// In en, this message translates to:
  /// **'Every chat, message, contact and setting stored by Imo LIVE on this device is removed. Your account is not deleted, so your chats are restored from the cloud the next time you are online.'**
  String get everyChatMessageContactAnd2;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @textSizeScalesEveryScreen.
  ///
  /// In en, this message translates to:
  /// **'Text size scales every screen. Chat bubbles additionally honour the per-chat font size in Chat settings.'**
  String get textSizeScalesEveryScreen;

  /// No description provided for @changingTheLauncherIconIs2.
  ///
  /// In en, this message translates to:
  /// **'Changing the launcher icon is a platform action. The choice is saved here and applied by the host app shell.'**
  String get changingTheLauncherIconIs2;

  /// No description provided for @blockedContactsCannotMessageOr2.
  ///
  /// In en, this message translates to:
  /// **'Blocked contacts cannot message or call you from this device. Use the + button to block someone.'**
  String get blockedContactsCannotMessageOr2;

  /// No description provided for @unblockingRestoresTheContactTo2.
  ///
  /// In en, this message translates to:
  /// **'Unblocking restores the contact to your chat list and removes the block flag.'**
  String get unblockingRestoresTheContactTo2;

  /// No description provided for @thisContactWillBeAble2.
  ///
  /// In en, this message translates to:
  /// **'This contact will be able to reach you again from this device.'**
  String get thisContactWillBeAble2;

  /// No description provided for @newMessagesStayInThe2.
  ///
  /// In en, this message translates to:
  /// **'New messages stay in the archive instead of returning the chat to your main list'**
  String get newMessagesStayInThe2;

  /// No description provided for @chatPreferencesReturnToTheir2.
  ///
  /// In en, this message translates to:
  /// **'Chat preferences return to their defaults. No chats or messages are deleted.'**
  String get chatPreferencesReturnToTheir2;

  /// No description provided for @offerToAddANumber2.
  ///
  /// In en, this message translates to:
  /// **'Offer to add a number to your device address book when you save a new contact'**
  String get offerToAddANumber2;

  /// No description provided for @translationsAreBundledWithThe2.
  ///
  /// In en, this message translates to:
  /// **'Translations are bundled with the app as ARB resources. Languages marked \"Coming soon\" are listed so the roadmap is visible, but switching to them leaves the interface in English.'**
  String get translationsAreBundledWithThe2;

  /// No description provided for @imoLIVEFollowsYourDevice2.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE follows your device setting so timestamps stay consistent with the rest of your phone. Change it in your system settings.'**
  String get imoLIVEFollowsYourDevice2;

  /// No description provided for @pairingASecondDeviceIs2.
  ///
  /// In en, this message translates to:
  /// **'Pairing a second device is not available yet. This screen lists the device you are using and explains what pairing would do — it never fabricates a successful link.'**
  String get pairingASecondDeviceIs2;

  /// No description provided for @openImoLIVEOnAnother2.
  ///
  /// In en, this message translates to:
  /// **'Open Imo LIVE on another device and scan this code. Pairing is not available yet, so this code will not complete a link.'**
  String get openImoLIVEOnAnother2;

  /// No description provided for @unlinkingRemovesADeviceFrom2.
  ///
  /// In en, this message translates to:
  /// **'Unlinking removes a device from this list. Because pairing is not implemented, revoking a real session is not possible yet.'**
  String get unlinkingRemovesADeviceFrom2;

  /// No description provided for @theDeviceIsRemovedFrom2.
  ///
  /// In en, this message translates to:
  /// **'The device is removed from this local list. No remote session exists to revoke.'**
  String get theDeviceIsRemovedFrom2;

  /// No description provided for @aListIsASaved2.
  ///
  /// In en, this message translates to:
  /// **'A list is a saved filter over your chats. Tapping one applies it to the Chats tab immediately.'**
  String get aListIsASaved2;

  /// No description provided for @theWorkListIsA2.
  ///
  /// In en, this message translates to:
  /// **'The Work list is a flag stored on each chat, so it survives restarts and applies on every device. Use Manage to choose which chats belong to it.'**
  String get theWorkListIsA2;

  /// No description provided for @notificationsAreDeliveredLocallyBy2.
  ///
  /// In en, this message translates to:
  /// **'Notifications are delivered locally by the OS. There is no push service, so nothing arrives while the app is fully closed — scheduled call reminders still fire because they are posted through the platform scheduler.'**
  String get notificationsAreDeliveredLocallyBy2;

  /// No description provided for @theseSwitchesControlWhatImo2.
  ///
  /// In en, this message translates to:
  /// **'These switches control what Imo LIVE stores and displays on this device. Enforcing them for other people — hiding your last seen from their phone, for example — needs the other side to honour it, which is not implemented yet.'**
  String get theseSwitchesControlWhatImo2;

  /// No description provided for @changingLastSeenAlsoAffects2.
  ///
  /// In en, this message translates to:
  /// **'Changing \"Last seen\" also affects read receipts in a backed build. Locally they are independent switches.'**
  String get changingLastSeenAlsoAffects2;

  /// No description provided for @sendDeliveryAndReadTicks2.
  ///
  /// In en, this message translates to:
  /// **'Send delivery and read ticks. Turning this off stops the local tick upgrade for new messages.'**
  String get sendDeliveryAndReadTicks2;

  /// No description provided for @imoLIVEWillAskFor2.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE will ask for your device credential on next launch. Biometric prompts are handled by the OS, so no biometric data ever reaches this app.'**
  String get imoLIVEWillAskFor2;

  /// No description provided for @allowSharingYourCurrentLocation2.
  ///
  /// In en, this message translates to:
  /// **'Allow sharing your current location inside chats. Location is only read the moment you press send.'**
  String get allowSharingYourCurrentLocation2;

  /// No description provided for @imoLIVEDoesNotClaim2.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE does not claim end-to-end encryption. Messages travel over TLS to Cloud Firestore and media goes to Cloudflare R2, so those servers can read them. Add a real key-exchange and encryption layer before advertising any encryption guarantee.'**
  String get imoLIVEDoesNotClaim2;

  /// No description provided for @allPrivacyOptionsReturnTo2.
  ///
  /// In en, this message translates to:
  /// **'All privacy options return to their defaults. Your chats, contacts and messages are untouched.'**
  String get allPrivacyOptionsReturnTo2;

  /// No description provided for @theSwitchMatchesTheSystem2.
  ///
  /// In en, this message translates to:
  /// **'The switch matches the system while \"System\" is selected. Flipping it pins light or dark until you change it again.'**
  String get theSwitchMatchesTheSystem2;

  /// No description provided for @photosVideosVoiceNotesAnd2.
  ///
  /// In en, this message translates to:
  /// **'Photos, videos, voice notes and documents you send or receive are saved here and counted below.'**
  String get photosVideosVoiceNotesAnd2;

  /// No description provided for @removesMessagesWhoseDisappearingTimer2.
  ///
  /// In en, this message translates to:
  /// **'Removes messages whose disappearing timer already elapsed'**
  String get removesMessagesWhoseDisappearingTimer2;

  /// No description provided for @followAChannelFromThe2.
  ///
  /// In en, this message translates to:
  /// **'Follow a channel from the Updates tab and it will appear here with its notification settings.'**
  String get followAChannelFromThe2;

  /// No description provided for @mutingAChannelKeepsIt2.
  ///
  /// In en, this message translates to:
  /// **'Muting a channel keeps it in your list but silences its updates badge.'**
  String get mutingAChannelKeepsIt2;

  /// No description provided for @theCopiedImageFileIs2.
  ///
  /// In en, this message translates to:
  /// **'The copied image file is deleted and the default pattern is restored.'**
  String get theCopiedImageFileIs2;

  /// No description provided for @allMessagesInThisChat2.
  ///
  /// In en, this message translates to:
  /// **'All messages in this chat will be deleted from this device. This cannot be undone.'**
  String get allMessagesInThisChat2;

  /// No description provided for @thisConversationAndAllIts2.
  ///
  /// In en, this message translates to:
  /// **'This conversation and all its messages will be removed from this device.'**
  String get thisConversationAndAllIts2;

  /// No description provided for @changeMedia.
  ///
  /// In en, this message translates to:
  /// **'Change media'**
  String get changeMedia;

  /// No description provided for @shareATextPhotoOr2.
  ///
  /// In en, this message translates to:
  /// **'Share a text, photo or video update. It disappears for everyone after 24 hours.'**
  String get shareATextPhotoOr2;

  /// No description provided for @updatesAreStoredOnThis2.
  ///
  /// In en, this message translates to:
  /// **'Updates are stored on this device only. Expiry after 24 hours is enforced locally.'**
  String get updatesAreStoredOnThis2;

  /// No description provided for @enterYourEmailFirstThen.
  ///
  /// In en, this message translates to:
  /// **'Enter your email first, then tap Forgot password.'**
  String get enterYourEmailFirstThen;

  /// No description provided for @aNewCodeIsOn.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way'**
  String get aNewCodeIsOn;

  /// No description provided for @thePhotoCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be uploaded. It is saved on this device and will sync once R2 storage is configured.'**
  String get thePhotoCouldNotBe;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @callLogCleared.
  ///
  /// In en, this message translates to:
  /// **'Call log cleared'**
  String get callLogCleared;

  /// No description provided for @reminderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Reminder cancelled'**
  String get reminderCancelled;

  /// No description provided for @clipboardIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardIsEmpty;

  /// No description provided for @addAContactFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a contact first'**
  String get addAContactFirst;

  /// No description provided for @reminderRemoved.
  ///
  /// In en, this message translates to:
  /// **'Reminder removed'**
  String get reminderRemoved;

  /// No description provided for @pickATimeInThe.
  ///
  /// In en, this message translates to:
  /// **'Pick a time in the future'**
  String get pickATimeInThe;

  /// No description provided for @reminderSaved.
  ///
  /// In en, this message translates to:
  /// **'Reminder saved'**
  String get reminderSaved;

  /// No description provided for @requestRejected.
  ///
  /// In en, this message translates to:
  /// **'Request rejected'**
  String get requestRejected;

  /// No description provided for @galleryPermissionIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Gallery permission is required'**
  String get galleryPermissionIsRequired;

  /// No description provided for @videoPermissionIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Video permission is required'**
  String get videoPermissionIsRequired;

  /// No description provided for @writeSomethingOrAttachA.
  ///
  /// In en, this message translates to:
  /// **'Write something or attach a file first'**
  String get writeSomethingOrAttachA;

  /// No description provided for @uploadFailedThePostWas.
  ///
  /// In en, this message translates to:
  /// **'Upload failed — the post was not published'**
  String get uploadFailedThePostWas;

  /// No description provided for @couldNotPublishCheckYour.
  ///
  /// In en, this message translates to:
  /// **'Could not publish — check your connection'**
  String get couldNotPublishCheckYour;

  /// No description provided for @postDeleted.
  ///
  /// In en, this message translates to:
  /// **'Post deleted'**
  String get postDeleted;

  /// No description provided for @thisAttachmentHasNoUsable.
  ///
  /// In en, this message translates to:
  /// **'This attachment has no usable link'**
  String get thisAttachmentHasNoUsable;

  /// No description provided for @noAppOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'No app on this device can open that file'**
  String get noAppOnThisDevice;

  /// No description provided for @requestSentTheOwnerWill.
  ///
  /// In en, this message translates to:
  /// **'Request sent — the owner will review it'**
  String get requestSentTheOwnerWill;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite link copied'**
  String get inviteLinkCopied;

  /// No description provided for @applicationSentForReview.
  ///
  /// In en, this message translates to:
  /// **'Application sent for review'**
  String get applicationSentForReview;

  /// No description provided for @secretKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Secret key copied'**
  String get secretKeyCopied;

  /// No description provided for @uploadFailedCheckTheStorage.
  ///
  /// In en, this message translates to:
  /// **'Upload failed — check the storage configuration'**
  String get uploadFailedCheckTheStorage;

  /// No description provided for @aChannelNeedsAName.
  ///
  /// In en, this message translates to:
  /// **'A channel needs a name'**
  String get aChannelNeedsAName;

  /// No description provided for @couldNotSaveIsThe.
  ///
  /// In en, this message translates to:
  /// **'Could not save — is the network up?'**
  String get couldNotSaveIsThe;

  /// No description provided for @channelUpdated.
  ///
  /// In en, this message translates to:
  /// **'Channel updated'**
  String get channelUpdated;

  /// No description provided for @applicationSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Application submitted'**
  String get applicationSubmitted;

  /// No description provided for @savedOnThisDeviceThe.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device — the server write failed, so followers cannot see it yet'**
  String get savedOnThisDeviceThe;

  /// No description provided for @allChatsRestored.
  ///
  /// In en, this message translates to:
  /// **'All chats restored'**
  String get allChatsRestored;

  /// No description provided for @listRenamed.
  ///
  /// In en, this message translates to:
  /// **'List renamed'**
  String get listRenamed;

  /// No description provided for @listDeleted.
  ///
  /// In en, this message translates to:
  /// **'List deleted'**
  String get listDeleted;

  /// No description provided for @recipientsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recipients updated'**
  String get recipientsUpdated;

  /// No description provided for @addAtLeastOneRecipient.
  ///
  /// In en, this message translates to:
  /// **'Add at least one recipient first'**
  String get addAtLeastOneRecipient;

  /// No description provided for @couldNotReadTheCaptured.
  ///
  /// In en, this message translates to:
  /// **'Could not read the captured photo'**
  String get couldNotReadTheCaptured;

  /// No description provided for @thisConversationIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'This conversation is no longer available'**
  String get thisConversationIsNoLonger;

  /// No description provided for @messageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Message updated'**
  String get messageUpdated;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get messageCopied;

  /// No description provided for @thatMessageIsTooOld.
  ///
  /// In en, this message translates to:
  /// **'That message is too old to delete for everyone'**
  String get thatMessageIsTooOld;

  /// No description provided for @chatCleared.
  ///
  /// In en, this message translates to:
  /// **'Chat cleared'**
  String get chatCleared;

  /// No description provided for @channelsAndBroadcastsHaveNo.
  ///
  /// In en, this message translates to:
  /// **'Channels and broadcasts have no personal profile'**
  String get channelsAndBroadcastsHaveNo;

  /// No description provided for @thisChatHasNoLinked.
  ///
  /// In en, this message translates to:
  /// **'This chat has no linked profile yet'**
  String get thisChatHasNoLinked;

  /// No description provided for @thisMessageHasNothingTo.
  ///
  /// In en, this message translates to:
  /// **'This message has nothing to save'**
  String get thisMessageHasNothingTo;

  /// No description provided for @savedToDeviceStorage.
  ///
  /// In en, this message translates to:
  /// **'Saved to device storage'**
  String get savedToDeviceStorage;

  /// No description provided for @thisMessageHasNothingTo2.
  ///
  /// In en, this message translates to:
  /// **'This message has nothing to share'**
  String get thisMessageHasNothingTo2;

  /// No description provided for @thatMessageIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'That message is no longer available'**
  String get thatMessageIsNoLonger;

  /// No description provided for @thisMediaIsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This media is not available on this device'**
  String get thisMediaIsNotAvailable;

  /// No description provided for @coordinatesAreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Coordinates are unavailable'**
  String get coordinatesAreUnavailable;

  /// No description provided for @noMapApplicationIsInstalled.
  ///
  /// In en, this message translates to:
  /// **'No map application is installed'**
  String get noMapApplicationIsInstalled;

  /// No description provided for @thisContactIsNotIn.
  ///
  /// In en, this message translates to:
  /// **'This contact is not in your list'**
  String get thisContactIsNotIn;

  /// No description provided for @thisFileIsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This file is not available'**
  String get thisFileIsNotAvailable;

  /// No description provided for @noLinkFoundInThat.
  ///
  /// In en, this message translates to:
  /// **'No link found in that message'**
  String get noLinkFoundInThat;

  /// No description provided for @thatLinkIsNotValid.
  ///
  /// In en, this message translates to:
  /// **'That link is not valid'**
  String get thatLinkIsNotValid;

  /// No description provided for @noBrowserOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'No browser on this device could open that link'**
  String get noBrowserOnThisDevice;

  /// No description provided for @thisAttachmentIsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This attachment is not available on this device'**
  String get thisAttachmentIsNotAvailable;

  /// No description provided for @nothingToCopy.
  ///
  /// In en, this message translates to:
  /// **'Nothing to copy'**
  String get nothingToCopy;

  /// No description provided for @copied2.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied2;

  /// No description provided for @starRemoved.
  ///
  /// In en, this message translates to:
  /// **'Star removed'**
  String get starRemoved;

  /// No description provided for @allStarsRemoved.
  ///
  /// In en, this message translates to:
  /// **'All stars removed'**
  String get allStarsRemoved;

  /// No description provided for @announcementChatIsNotReady.
  ///
  /// In en, this message translates to:
  /// **'Announcement chat is not ready yet'**
  String get announcementChatIsNotReady;

  /// No description provided for @communityRenamed.
  ///
  /// In en, this message translates to:
  /// **'Community renamed'**
  String get communityRenamed;

  /// No description provided for @descriptionUpdated.
  ///
  /// In en, this message translates to:
  /// **'Description updated'**
  String get descriptionUpdated;

  /// No description provided for @everyGroupIsAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'Every group is already in this community'**
  String get everyGroupIsAlreadyIn;

  /// No description provided for @communityDeleted.
  ///
  /// In en, this message translates to:
  /// **'Community deleted'**
  String get communityDeleted;

  /// No description provided for @noContactsFoundCheckContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts found. Check contacts permission in system settings.'**
  String get noContactsFoundCheckContacts;

  /// No description provided for @aboutUpdated.
  ///
  /// In en, this message translates to:
  /// **'About updated'**
  String get aboutUpdated;

  /// No description provided for @phoneNumberCopied.
  ///
  /// In en, this message translates to:
  /// **'Phone number copied'**
  String get phoneNumberCopied;

  /// No description provided for @chatDeleted.
  ///
  /// In en, this message translates to:
  /// **'Chat deleted'**
  String get chatDeleted;

  /// No description provided for @contactDeleted.
  ///
  /// In en, this message translates to:
  /// **'Contact deleted'**
  String get contactDeleted;

  /// No description provided for @noProfilePhotoSet.
  ///
  /// In en, this message translates to:
  /// **'No profile photo set'**
  String get noProfilePhotoSet;

  /// No description provided for @aFirstNameAndPhone.
  ///
  /// In en, this message translates to:
  /// **'A first name and phone number are required'**
  String get aFirstNameAndPhone;

  /// No description provided for @noNewContactsFoundIn.
  ///
  /// In en, this message translates to:
  /// **'No new contacts found in your address book'**
  String get noNewContactsFoundIn;

  /// No description provided for @watchTheWholeAdTo.
  ///
  /// In en, this message translates to:
  /// **'Watch the whole ad to earn points'**
  String get watchTheWholeAdTo;

  /// No description provided for @groupMessagesCleared.
  ///
  /// In en, this message translates to:
  /// **'Group messages cleared'**
  String get groupMessagesCleared;

  /// No description provided for @groupNameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Group name updated'**
  String get groupNameUpdated;

  /// No description provided for @groupDeleted.
  ///
  /// In en, this message translates to:
  /// **'Group deleted'**
  String get groupDeleted;

  /// No description provided for @couldNotReadTheSelected.
  ///
  /// In en, this message translates to:
  /// **'Could not read the selected image'**
  String get couldNotReadTheSelected;

  /// No description provided for @groupCreated.
  ///
  /// In en, this message translates to:
  /// **'Group created'**
  String get groupCreated;

  /// No description provided for @noAppCanHandleThat.
  ///
  /// In en, this message translates to:
  /// **'No app can handle that link'**
  String get noAppCanHandleThat;

  /// No description provided for @allChatsMarkedAsRead.
  ///
  /// In en, this message translates to:
  /// **'All chats marked as read'**
  String get allChatsMarkedAsRead;

  /// No description provided for @aFirstNameIsRequired.
  ///
  /// In en, this message translates to:
  /// **'A first name is required'**
  String get aFirstNameIsRequired;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdated;

  /// No description provided for @photoUpdatedTapSaveTo.
  ///
  /// In en, this message translates to:
  /// **'Photo updated — tap Save to keep it'**
  String get photoUpdatedTapSaveTo;

  /// No description provided for @numberUpdatedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Number updated on this device'**
  String get numberUpdatedOnThisDevice;

  /// No description provided for @allLocalDataCleared.
  ///
  /// In en, this message translates to:
  /// **'All local data cleared'**
  String get allLocalDataCleared;

  /// No description provided for @appearanceRestoredToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Appearance restored to defaults'**
  String get appearanceRestoredToDefaults;

  /// No description provided for @everyContactIsAlreadyBlocked.
  ///
  /// In en, this message translates to:
  /// **'Every contact is already blocked'**
  String get everyContactIsAlreadyBlocked;

  /// No description provided for @chatSettingsReset.
  ///
  /// In en, this message translates to:
  /// **'Chat settings reset'**
  String get chatSettingsReset;

  /// No description provided for @linkedDevicesCleared.
  ///
  /// In en, this message translates to:
  /// **'Linked devices cleared'**
  String get linkedDevicesCleared;

  /// No description provided for @showingAllChats.
  ///
  /// In en, this message translates to:
  /// **'Showing all chats'**
  String get showingAllChats;

  /// No description provided for @noChatsToOrganiseYet.
  ///
  /// In en, this message translates to:
  /// **'No chats to organise yet'**
  String get noChatsToOrganiseYet;

  /// No description provided for @testNotificationPosted.
  ///
  /// In en, this message translates to:
  /// **'Test notification posted'**
  String get testNotificationPosted;

  /// No description provided for @notificationSettingsReset.
  ///
  /// In en, this message translates to:
  /// **'Notification settings reset'**
  String get notificationSettingsReset;

  /// No description provided for @privacySettingsReset.
  ///
  /// In en, this message translates to:
  /// **'Privacy settings reset'**
  String get privacySettingsReset;

  /// No description provided for @noMediaFilesToDelete.
  ///
  /// In en, this message translates to:
  /// **'No media files to delete'**
  String get noMediaFilesToDelete;

  /// No description provided for @allMediaFilesDeleted.
  ///
  /// In en, this message translates to:
  /// **'All media files deleted'**
  String get allMediaFilesDeleted;

  /// No description provided for @subscriptionsRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions refreshed'**
  String get subscriptionsRefreshed;

  /// No description provided for @defaultRestored.
  ///
  /// In en, this message translates to:
  /// **'Default restored'**
  String get defaultRestored;

  /// No description provided for @wallpaperRemoved.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper removed'**
  String get wallpaperRemoved;

  /// No description provided for @wallpaperApplied.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper applied'**
  String get wallpaperApplied;

  /// No description provided for @updateShared.
  ///
  /// In en, this message translates to:
  /// **'Update shared'**
  String get updateShared;

  /// No description provided for @statusRepliesNeedAChat.
  ///
  /// In en, this message translates to:
  /// **'Status replies need a chat thread — open your chat with the author.'**
  String get statusRepliesNeedAChat;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @bengali.
  ///
  /// In en, this message translates to:
  /// **'Bengali'**
  String get bengali;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get hindi;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @portuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get portuguese;

  /// No description provided for @russian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get russian;

  /// No description provided for @indonesian.
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get indonesian;

  /// No description provided for @turkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get turkish;

  /// No description provided for @chinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get chinese;

  /// No description provided for @japanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get japanese;

  /// No description provided for @roundedBubbles.
  ///
  /// In en, this message translates to:
  /// **'Rounded bubbles'**
  String get roundedBubbles;

  /// No description provided for @compact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get compact;

  /// No description provided for @outlined.
  ///
  /// In en, this message translates to:
  /// **'Outlined'**
  String get outlined;

  /// No description provided for @imoRose.
  ///
  /// In en, this message translates to:
  /// **'Imo Rose'**
  String get imoRose;

  /// No description provided for @monochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get monochrome;

  /// No description provided for @midnight.
  ///
  /// In en, this message translates to:
  /// **'Midnight'**
  String get midnight;

  /// No description provided for @classic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get classic;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @voiceMessages.
  ///
  /// In en, this message translates to:
  /// **'Voice messages'**
  String get voiceMessages;

  /// No description provided for @profilePhotos.
  ///
  /// In en, this message translates to:
  /// **'Profile photos'**
  String get profilePhotos;

  /// No description provided for @wallpapers.
  ///
  /// In en, this message translates to:
  /// **'Wallpapers'**
  String get wallpapers;

  /// No description provided for @statusMedia.
  ///
  /// In en, this message translates to:
  /// **'Status media'**
  String get statusMedia;

  /// No description provided for @anyImoLiveUser.
  ///
  /// In en, this message translates to:
  /// **'Any Imo LIVE user'**
  String get anyImoLiveUser;

  /// No description provided for @myContacts.
  ///
  /// In en, this message translates to:
  /// **'My contacts'**
  String get myContacts;

  /// No description provided for @peopleYouSaved.
  ///
  /// In en, this message translates to:
  /// **'People you saved'**
  String get peopleYouSaved;

  /// No description provided for @nobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get nobody;

  /// No description provided for @hideCompletely.
  ///
  /// In en, this message translates to:
  /// **'Hide completely'**
  String get hideCompletely;

  /// No description provided for @seconds3.
  ///
  /// In en, this message translates to:
  /// **'3s'**
  String get seconds3;

  /// No description provided for @seconds5.
  ///
  /// In en, this message translates to:
  /// **'5s'**
  String get seconds5;

  /// No description provided for @seconds10.
  ///
  /// In en, this message translates to:
  /// **'10s'**
  String get seconds10;

  /// No description provided for @seconds30.
  ///
  /// In en, this message translates to:
  /// **'30s'**
  String get seconds30;

  /// No description provided for @unreadMessagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unread messages'**
  String unreadMessagesCount(int count);

  /// No description provided for @resetLinkSentTo.
  ///
  /// In en, this message translates to:
  /// **'Reset link sent to {email}'**
  String resetLinkSentTo(String email);

  /// No description provided for @channelCreatedName.
  ///
  /// In en, this message translates to:
  /// **'{name} created'**
  String channelCreatedName(String name);

  /// No description provided for @shareSecretKeyFor.
  ///
  /// In en, this message translates to:
  /// **'Share this with the people you want to let into {channel}. It is shown only once.'**
  String shareSecretKeyFor(String channel);

  /// No description provided for @countSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String countSelected(int count);

  /// No description provided for @nameIsTyping.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing...'**
  String nameIsTyping(String name);

  /// No description provided for @pollGoingMaybe.
  ///
  /// In en, this message translates to:
  /// **'{going} going · {maybe} maybe'**
  String pollGoingMaybe(int going, int maybe);

  /// No description provided for @communityCreatedName.
  ///
  /// In en, this message translates to:
  /// **'{name} created'**
  String communityCreatedName(String name);

  /// No description provided for @featureNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'{feature} is not available yet'**
  String featureNotAvailableYet(String feature);

  /// No description provided for @sendInviteTo.
  ///
  /// In en, this message translates to:
  /// **'Send {target} an invite so they can join you on Imo LIVE?'**
  String sendInviteTo(String target);

  /// No description provided for @inviteSentTo.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {target}'**
  String inviteSentTo(String target);

  /// No description provided for @nothingMatchesQuery.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\". Try a different word or filter.'**
  String nothingMatchesQuery(String query);

  /// No description provided for @countrySetTo.
  ///
  /// In en, this message translates to:
  /// **'Country set to {country}'**
  String countrySetTo(String country);

  /// No description provided for @whatShouldListContain.
  ///
  /// In en, this message translates to:
  /// **'What should \"{name}\" contain?'**
  String whatShouldListContain(String name);

  /// No description provided for @listCreatedAndApplied.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" created and applied'**
  String listCreatedAndApplied(String name);

  /// No description provided for @channelStats.
  ///
  /// In en, this message translates to:
  /// **'{handle} · {followers} followers · {reactions} reactions'**
  String channelStats(Object handle, Object followers, Object reactions);

  /// No description provided for @recipientsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recipient} other{{count} recipients}}'**
  String recipientsCount(int count);

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search {title}'**
  String searchTitle(Object title);

  /// No description provided for @resultsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String resultsCount(int count);

  /// No description provided for @starredMessagesUnstarred.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 starred message is unstarred. The messages themselves are untouched.} other{{count} starred messages are unstarred. The messages themselves are untouched.}}'**
  String starredMessagesUnstarred(int count);

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String membersCount(int count);

  /// No description provided for @contactsImported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 contact} other{Imported {count} contacts}}'**
  String contactsImported(int count);

  /// No description provided for @xRemovedFromYourList.
  ///
  /// In en, this message translates to:
  /// **'{name} is removed from your list. Existing chats stay in place.'**
  String xRemovedFromYourList(Object name);

  /// No description provided for @addedX.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String addedX(Object name);

  /// No description provided for @membersAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 member} other{Added {count} members}}'**
  String membersAdded(int count);

  /// No description provided for @thisDeviceShowsYouAs.
  ///
  /// In en, this message translates to:
  /// **'This device shows you as {state}'**
  String thisDeviceShowsYouAs(Object state);

  /// No description provided for @platformLastActive.
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform}\nLast active: {lastActive}\n{note}'**
  String platformLastActive(Object platform, Object lastActive, Object note);

  /// No description provided for @thisChat.
  ///
  /// In en, this message translates to:
  /// **'this chat'**
  String get thisChat;

  /// No description provided for @thisContact.
  ///
  /// In en, this message translates to:
  /// **'This contact'**
  String get thisContact;

  /// No description provided for @thisIsTheDeviceYou.
  ///
  /// In en, this message translates to:
  /// **'This is the device you are using now.'**
  String get thisIsTheDeviceYou;

  /// No description provided for @linkedDeviceEntriesAre.
  ///
  /// In en, this message translates to:
  /// **'Linked device entries are stored locally.'**
  String get linkedDeviceEntriesAre;

  /// No description provided for @resendInS.
  ///
  /// In en, this message translates to:
  /// **'Resend in {secondsLeft}s'**
  String resendInS(Object secondsLeft);

  /// No description provided for @onIsDeleted.
  ///
  /// In en, this message translates to:
  /// **'{title} on {fullTimestamp} is deleted.'**
  String onIsDeleted(Object title, Object fullTimestamp);

  /// No description provided for @canNowJoin.
  ///
  /// In en, this message translates to:
  /// **'{displayName} can now join'**
  String canNowJoin(Object displayName);

  /// No description provided for @postedTo.
  ///
  /// In en, this message translates to:
  /// **'Posted to {nameValue}'**
  String postedTo(Object nameValue);

  /// No description provided for @followers2.
  ///
  /// In en, this message translates to:
  /// **'{category} · {compactCount} followers'**
  String followers2(Object category, Object compactCount);

  /// No description provided for @followersWillFindYouAs.
  ///
  /// In en, this message translates to:
  /// **'Followers will find you as @{handle}'**
  String followersWillFindYouAs(Object handle);

  /// No description provided for @restored.
  ///
  /// In en, this message translates to:
  /// **'{title} restored'**
  String restored(Object title);

  /// No description provided for @delete2.
  ///
  /// In en, this message translates to:
  /// **'Delete {nameValue}?'**
  String delete2(Object nameValue);

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'{trim} created'**
  String created(Object trim);

  /// No description provided for @broadcastToPeople.
  ///
  /// In en, this message translates to:
  /// **'Broadcast to {length} people'**
  String broadcastToPeople(Object length);

  /// No description provided for @recipients.
  ///
  /// In en, this message translates to:
  /// **'{length} recipients'**
  String recipients(Object length);

  /// No description provided for @forwardedTo.
  ///
  /// In en, this message translates to:
  /// **'Forwarded to {title}'**
  String forwardedTo(Object title);

  /// No description provided for @messageSDeleted.
  ///
  /// In en, this message translates to:
  /// **'{length} message(s) deleted'**
  String messageSDeleted(Object length);

  /// No description provided for @messageSStarred.
  ///
  /// In en, this message translates to:
  /// **'{length} message(s) starred'**
  String messageSStarred(Object length);

  /// No description provided for @couldNotSaveTheFile.
  ///
  /// In en, this message translates to:
  /// **'Could not save the file: {e}'**
  String couldNotSaveTheFile(Object e);

  /// No description provided for @couldNotShare.
  ///
  /// In en, this message translates to:
  /// **'Could not share: {e}'**
  String couldNotShare(Object e);

  /// No description provided for @links.
  ///
  /// In en, this message translates to:
  /// **'Links ({length})'**
  String links(Object length);

  /// No description provided for @option.
  ///
  /// In en, this message translates to:
  /// **'Option {index}'**
  String option(Object index);

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'{grouped} points'**
  String points(Object grouped);

  /// No description provided for @delete3.
  ///
  /// In en, this message translates to:
  /// **'Delete {nameValue}?'**
  String delete3(Object nameValue);

  /// No description provided for @added.
  ///
  /// In en, this message translates to:
  /// **'{nameValue} added'**
  String added(Object nameValue);

  /// No description provided for @inviteTo.
  ///
  /// In en, this message translates to:
  /// **'Invite to {nameValue}'**
  String inviteTo(Object nameValue);

  /// No description provided for @members2.
  ///
  /// In en, this message translates to:
  /// **'Members ({length})'**
  String members2(Object length);

  /// No description provided for @theWholeConversationWithAnd.
  ///
  /// In en, this message translates to:
  /// **'The whole conversation with {fullName} and its messages are removed from this device.'**
  String theWholeConversationWithAnd(Object fullName);

  /// No description provided for @removesFromYourContactList.
  ///
  /// In en, this message translates to:
  /// **'Removes {fullName} from your contact list'**
  String removesFromYourContactList(Object fullName);

  /// No description provided for @delete4.
  ///
  /// In en, this message translates to:
  /// **'Delete {fullName}?'**
  String delete4(Object fullName);

  /// No description provided for @countriesAndTerritoriesStoresYour.
  ///
  /// In en, this message translates to:
  /// **'{length} countries and territories · {appName} stores your choice locally'**
  String countriesAndTerritoriesStoresYour(Object length, Object appName);

  /// No description provided for @alreadyUsesSaveAnotherContact.
  ///
  /// In en, this message translates to:
  /// **'{fullName} already uses {normalised}. Save another contact with the same number?'**
  String alreadyUsesSaveAnotherContact(Object fullName, Object normalised);

  /// No description provided for @contactUpdated.
  ///
  /// In en, this message translates to:
  /// **'Contact updated: {labelFor}'**
  String contactUpdated(Object labelFor);

  /// No description provided for @contactSaved.
  ///
  /// In en, this message translates to:
  /// **'Contact saved: {labelFor}'**
  String contactSaved(Object labelFor);

  /// No description provided for @continueWith.
  ///
  /// In en, this message translates to:
  /// **'Continue with {length}'**
  String continueWith(Object length);

  /// No description provided for @getOfPremium.
  ///
  /// In en, this message translates to:
  /// **'Get {nameValue} of Premium?'**
  String getOfPremium(Object nameValue);

  /// No description provided for @thisSpendsPointsFromYour.
  ///
  /// In en, this message translates to:
  /// **'This spends {grouped} points from your balance. Your remaining points stay yours.'**
  String thisSpendsPointsFromYour(Object grouped);

  /// No description provided for @earnPointsPerAd.
  ///
  /// In en, this message translates to:
  /// **'Earn {pointsPerAd} points per ad'**
  String earnPointsPerAd(Object pointsPerAd);

  /// No description provided for @ofAds.
  ///
  /// In en, this message translates to:
  /// **'{watched} of {dailyAdLimit} ads'**
  String ofAds(Object watched, Object dailyAdLimit);

  /// No description provided for @premiumIsActiveDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'Premium is active — {premiumDaysLeft} days left. Buying more extends it.'**
  String premiumIsActiveDaysLeft(Object premiumDaysLeft);

  /// No description provided for @points2.
  ///
  /// In en, this message translates to:
  /// **'{grouped} points'**
  String points2(Object grouped);

  /// No description provided for @group2.
  ///
  /// In en, this message translates to:
  /// **'Group · {members}'**
  String group2(Object members);

  /// No description provided for @created2.
  ///
  /// In en, this message translates to:
  /// **'Created {relative}'**
  String created2(Object relative);

  /// No description provided for @members3.
  ///
  /// In en, this message translates to:
  /// **'{memberCount} members'**
  String members3(Object memberCount);

  /// No description provided for @inviteMorePeopleTo.
  ///
  /// In en, this message translates to:
  /// **'Invite more people to {nameValue}'**
  String inviteMorePeopleTo(Object nameValue);

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave {nameValue}'**
  String leave(Object nameValue);

  /// No description provided for @everyMessageInIsPermanently.
  ///
  /// In en, this message translates to:
  /// **'Every message in {nameValue} is permanently deleted from this device. The group and its members stay in place.'**
  String everyMessageInIsPermanently(Object nameValue);

  /// No description provided for @inviteTo2.
  ///
  /// In en, this message translates to:
  /// **'Invite to {nameValue}'**
  String inviteTo2(Object nameValue);

  /// No description provided for @message2.
  ///
  /// In en, this message translates to:
  /// **'Message {firstName}'**
  String message2(Object firstName);

  /// No description provided for @remove2.
  ///
  /// In en, this message translates to:
  /// **'Remove {fullName}?'**
  String remove2(Object fullName);

  /// No description provided for @isRemovedFromGroupsAre.
  ///
  /// In en, this message translates to:
  /// **'{firstName} is removed from {nameValue}. Groups are stored on this device, so nobody else is notified.'**
  String isRemovedFromGroupsAre(Object firstName, Object nameValue);

  /// No description provided for @removed.
  ///
  /// In en, this message translates to:
  /// **'{firstName} removed'**
  String removed(Object firstName);

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit {nameValue}?'**
  String exit(Object nameValue);

  /// No description provided for @youLeft.
  ///
  /// In en, this message translates to:
  /// **'You left {nameValue}'**
  String youLeft(Object nameValue);

  /// No description provided for @delete5.
  ///
  /// In en, this message translates to:
  /// **'Delete {nameValue}?'**
  String delete5(Object nameValue);

  /// No description provided for @createdTheGroup.
  ///
  /// In en, this message translates to:
  /// **'{myName} created the group \"{nameValue}\"'**
  String createdTheGroup(Object myName, Object nameValue);

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'{length} selected'**
  String selected(Object length);

  /// No description provided for @add2.
  ///
  /// In en, this message translates to:
  /// **'Add {length}'**
  String add2(Object length);

  /// No description provided for @version2.
  ///
  /// In en, this message translates to:
  /// **'Version {appVersion}'**
  String version2(Object appVersion);

  /// No description provided for @searchResult.
  ///
  /// In en, this message translates to:
  /// **'Search result {title}'**
  String searchResult(Object title);

  /// No description provided for @appVersionNChatsNContactsNStarred.
  ///
  /// In en, this message translates to:
  /// **'App version: {appVersion}\nChats: {read}\nContacts: {read2}\nStarred messages: {read3}\nMedia stored: {read4} bytes\nNetwork: Firebase Authentication + Cloud Firestore'**
  String appVersionNChatsNContactsNStarred(
    Object appVersion,
    Object read,
    Object read2,
    Object read3,
    Object read4,
  );

  /// No description provided for @searchingBy.
  ///
  /// In en, this message translates to:
  /// **'Searching by {labelFor}'**
  String searchingBy(Object labelFor);

  /// No description provided for @sendAnInviteToSo.
  ///
  /// In en, this message translates to:
  /// **'Send an invite to {target} so they can join you on {appName}?'**
  String sendAnInviteToSo(Object target, Object appName);

  /// No description provided for @thisIsHowYourMessages2.
  ///
  /// In en, this message translates to:
  /// **'This is how your messages will look at {round}%.'**
  String thisIsHowYourMessages2(Object round);

  /// No description provided for @appIconSetTo.
  ///
  /// In en, this message translates to:
  /// **'App icon set to {label}'**
  String appIconSetTo(Object label);

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'{length} blocked'**
  String blocked(Object length);

  /// No description provided for @unblock2.
  ///
  /// In en, this message translates to:
  /// **'Unblock {fullName}?'**
  String unblock2(Object fullName);

  /// No description provided for @unblocked.
  ///
  /// In en, this message translates to:
  /// **'{fullName} unblocked'**
  String unblocked(Object fullName);

  /// No description provided for @blocked2.
  ///
  /// In en, this message translates to:
  /// **'{fullName} blocked'**
  String blocked2(Object fullName);

  /// No description provided for @languageSetTo.
  ///
  /// In en, this message translates to:
  /// **'Language set to {native}'**
  String languageSetTo(Object native);

  /// No description provided for @isComingSoon.
  ///
  /// In en, this message translates to:
  /// **'{native} is coming soon'**
  String isComingSoon(Object native);

  /// No description provided for @stringsHaveNotBeenTranslated.
  ///
  /// In en, this message translates to:
  /// **'{label} strings have not been translated yet. Add them by creating a new ARB file in lib/l10n and running the localization generator.'**
  String stringsHaveNotBeenTranslated(Object label);

  /// No description provided for @selectedFallingBackToEnglish.
  ///
  /// In en, this message translates to:
  /// **'{native} selected — falling back to English'**
  String selectedFallingBackToEnglish(Object native);

  /// No description provided for @unlink2.
  ///
  /// In en, this message translates to:
  /// **'Unlink {nameValue}?'**
  String unlink2(Object nameValue);

  /// No description provided for @unlinked.
  ///
  /// In en, this message translates to:
  /// **'Unlinked {nameValue}'**
  String unlinked(Object nameValue);

  /// No description provided for @chatsFlaggedAsWork.
  ///
  /// In en, this message translates to:
  /// **'{length} chats flagged as work'**
  String chatsFlaggedAsWork(Object length);

  /// No description provided for @couldNotReadLocalStorage.
  ///
  /// In en, this message translates to:
  /// **'Could not read local storage: {error}'**
  String couldNotReadLocalStorage(Object error);

  /// No description provided for @clear2.
  ///
  /// In en, this message translates to:
  /// **'Clear {folder}?'**
  String clear2(Object folder);

  /// No description provided for @thisPermanentlyDeletesOfLocal.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes {formatBytes} of local files. Chat messages stay in place but their attachments will no longer open.'**
  String thisPermanentlyDeletesOfLocal(Object formatBytes);

  /// No description provided for @cleared.
  ///
  /// In en, this message translates to:
  /// **'{folder} cleared'**
  String cleared(Object folder);

  /// No description provided for @removesOfImagesVideosAudio.
  ///
  /// In en, this message translates to:
  /// **'Removes {formatBytes} of images, videos, audio, voice notes and documents from this device. This cannot be undone.'**
  String removesOfImagesVideosAudio(Object formatBytes);

  /// No description provided for @followers3.
  ///
  /// In en, this message translates to:
  /// **'{members} followers · {category}'**
  String followers3(Object members, Object category);

  /// No description provided for @groupsMembers.
  ///
  /// In en, this message translates to:
  /// **'{length} groups · {length2} members'**
  String groupsMembers(Object length, Object length2);

  /// No description provided for @wallpaperSetTo.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper set to {nameValue}'**
  String wallpaperSetTo(Object nameValue);

  /// No description provided for @videoPlaybackNeedsAVideo.
  ///
  /// In en, this message translates to:
  /// **'Video playback needs a video player package.\nThe file is saved at:\n{path}'**
  String videoPlaybackNeedsAVideo(Object path);

  /// No description provided for @expiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {remaining}'**
  String expiresIn(Object remaining);

  /// No description provided for @thatScreenDoesnTExist.
  ///
  /// In en, this message translates to:
  /// **'That screen doesn\'t exist.'**
  String get thatScreenDoesnTExist;

  /// No description provided for @typing2.
  ///
  /// In en, this message translates to:
  /// **'typing'**
  String get typing2;

  /// No description provided for @weLlEmailYouA.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email you a link to choose a new password.'**
  String get weLlEmailYouA;

  /// No description provided for @weSentACodeTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a code to '**
  String get weSentACodeTo;

  /// No description provided for @username2.
  ///
  /// In en, this message translates to:
  /// **'username'**
  String get username2;

  /// No description provided for @nameUsernameDescriptionAvatarAnd.
  ///
  /// In en, this message translates to:
  /// **'Name, @username, description, avatar and cover'**
  String get nameUsernameDescriptionAvatarAnd;

  /// No description provided for @uniqueUsername.
  ///
  /// In en, this message translates to:
  /// **'Unique @username'**
  String get uniqueUsername;

  /// No description provided for @uniqueUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Unique @username (required)'**
  String get uniqueUsernameRequired;

  /// No description provided for @searchNameHandlePhoneOr.
  ///
  /// In en, this message translates to:
  /// **'Search name, @handle, phone or email'**
  String get searchNameHandlePhoneOr;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft: '**
  String get draft;

  /// No description provided for @theMessageIsRemovedFrom2.
  ///
  /// In en, this message translates to:
  /// **'The message is removed from this device and replaced with a \"deleted\" notice. It is also removed from the recipient\'s copy the next time their device syncs.\n\nYou can only do this within two days of sending.'**
  String get theMessageIsRemovedFrom2;

  /// No description provided for @deleteForMe2.
  ///
  /// In en, this message translates to:
  /// **'Delete for me?'**
  String get deleteForMe2;

  /// No description provided for @theseMessagesAreRemovedFromThisDeviceOnly.
  ///
  /// In en, this message translates to:
  /// **'These {length} messages are removed from this device only. The other person keeps their own copies and is not told about it.\n\nThis cannot be undone here.'**
  String theseMessagesAreRemovedFromThisDeviceOnly(Object length);

  /// No description provided for @thisMessageIsRemovedFromThisDeviceOnly.
  ///
  /// In en, this message translates to:
  /// **'This message is removed from this device only. The other person keeps their own copy and is not told about it.\n\nThis cannot be undone here.'**
  String get thisMessageIsRemovedFromThisDeviceOnly;

  /// No description provided for @alsoWriteThisPersonInto.
  ///
  /// In en, this message translates to:
  /// **'Also write this person into your phone\'s address book'**
  String get alsoWriteThisPersonInto;

  /// No description provided for @eGWeekendRiders.
  ///
  /// In en, this message translates to:
  /// **'e.g. Weekend Riders'**
  String get eGWeekendRiders;

  /// No description provided for @coreModelsServicesWidgetsConstants.
  ///
  /// In en, this message translates to:
  /// **'core/  — models, services, widgets, constants and formatters\n\napp/  — theme tokens, router and the root widget\n\nfeatures/<feature>/domain  — repository contracts\nfeatures/<feature>/data  — local implementations\nfeatures/<feature>/presentation  — screens, widgets, providers\n\nlocal/  — Hive database and file storage'**
  String get coreModelsServicesWidgetsConstants;

  /// No description provided for @liveNowSignInEmail.
  ///
  /// In en, this message translates to:
  /// **'Live now\n• Sign-in — email, Google and phone\n• Chat & message sync — Cloud Firestore, real time\n• People directory — phone, email, @handle or user id\n\nNeeds a value or a service\n• Cloudflare R2 — set the credentials in R2Config\n• Push delivery — FCM / APNs, so alerts arrive when closed\n• Device pairing — companion sessions\n\nNot implemented\n• End-to-end encryption — no key exchange or ciphertext transport\n• WebRTC — real-time audio and video calls'**
  String get liveNowSignInEmail;

  /// No description provided for @imoLIVEIsALocal.
  ///
  /// In en, this message translates to:
  /// **'Imo LIVE is a local-first messaging application. It provides no messaging service, no account and no data transmission. You are responsible for the content you create on this device.\n\nThis build ships no proprietary WhatsApp, Meta or third-party branding, and contains no code owned by those companies.'**
  String get imoLIVEIsALocal;

  /// No description provided for @eG8801711234567.
  ///
  /// In en, this message translates to:
  /// **'e.g. +880 1711 234567'**
  String get eG8801711234567;

  /// No description provided for @phoneEmailUsernameOrUser.
  ///
  /// In en, this message translates to:
  /// **'Phone, email, @username or user ID'**
  String get phoneEmailUsernameOrUser;

  /// No description provided for @eG8801712345678.
  ///
  /// In en, this message translates to:
  /// **'e.g. +880 1712 345678'**
  String get eG8801712345678;

  /// No description provided for @eGImouser042117.
  ///
  /// In en, this message translates to:
  /// **'e.g. @imouser_042117'**
  String get eGImouser042117;

  /// No description provided for @eGNameExampleCom.
  ///
  /// In en, this message translates to:
  /// **'e.g. name@example.com'**
  String get eGNameExampleCom;

  /// No description provided for @blockingHidesAContactS.
  ///
  /// In en, this message translates to:
  /// **'Blocking hides a contact\'s chats and calls on this device. The block is not sent to your account, so it applies here only.'**
  String get blockingHidesAContactS;

  /// No description provided for @everyNonCurrentEntryIs2.
  ///
  /// In en, this message translates to:
  /// **'Every non-current entry is deleted from this device\'s list. Remote sessions cannot be revoked yet.'**
  String get everyNonCurrentEntryIs2;

  /// No description provided for @pickedImagesAreCopiedInto.
  ///
  /// In en, this message translates to:
  /// **'Picked images are copied into the app\'s private storage, so they keep working even if you delete the original.'**
  String get pickedImagesAreCopiedInto;

  /// No description provided for @heyHowDoesThisWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Hey! How does this wallpaper look?'**
  String get heyHowDoesThisWallpaper;

  /// No description provided for @looksGreatInDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Looks great in dark mode.'**
  String get looksGreatInDarkMode;

  /// No description provided for @tryADifferentOneFrom.
  ///
  /// In en, this message translates to:
  /// **'Try a different one from the grid below.'**
  String get tryADifferentOneFrom;

  /// No description provided for @pointsAwarded.
  ///
  /// In en, this message translates to:
  /// **'+{points} points'**
  String pointsAwarded(Object points);

  /// No description provided for @couldNotAddPoints.
  ///
  /// In en, this message translates to:
  /// **'Could not add points — check your connection'**
  String get couldNotAddPoints;

  /// No description provided for @youNeedMorePointsFor.
  ///
  /// In en, this message translates to:
  /// **'You need {short} more points for {name}'**
  String youNeedMorePointsFor(Object short, Object name);

  /// No description provided for @couldNotActivatePremium.
  ///
  /// In en, this message translates to:
  /// **'Could not activate premium — check your connection'**
  String get couldNotActivatePremium;

  /// No description provided for @youNeedMorePointsForAGift.
  ///
  /// In en, this message translates to:
  /// **'You need {short} more points for a {name}'**
  String youNeedMorePointsForAGift(Object short, Object name);

  /// No description provided for @giftSent.
  ///
  /// In en, this message translates to:
  /// **'{emoji} {name} sent'**
  String giftSent(Object emoji, Object name);

  /// No description provided for @locationServicesAreOff.
  ///
  /// In en, this message translates to:
  /// **'Location services are turned off on this device.'**
  String get locationServicesAreOff;

  /// No description provided for @couldNotDetermineYourLocation.
  ///
  /// In en, this message translates to:
  /// **'Could not determine your location. {error}'**
  String couldNotDetermineYourLocation(Object error);

  /// No description provided for @microphoneAccessWasNot.
  ///
  /// In en, this message translates to:
  /// **'Microphone access was not granted.'**
  String get microphoneAccessWasNot;

  /// No description provided for @microphoneStillHeldByCall.
  ///
  /// In en, this message translates to:
  /// **'The microphone is still held by a call. Hang up and try again.'**
  String get microphoneStillHeldByCall;

  /// No description provided for @couldNotStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not start recording. {error}'**
  String couldNotStartRecording(Object error);

  /// No description provided for @noRecordingInProgress.
  ///
  /// In en, this message translates to:
  /// **'No recording in progress.'**
  String get noRecordingInProgress;

  /// No description provided for @recordingCouldNotBeSaved.
  ///
  /// In en, this message translates to:
  /// **'The recording could not be saved.'**
  String get recordingCouldNotBeSaved;

  /// No description provided for @couldNotFinishRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not finish the recording. {error}'**
  String couldNotFinishRecording(Object error);

  /// No description provided for @couldNotLoadTheImage.
  ///
  /// In en, this message translates to:
  /// **'Could not load the selected image. {error}'**
  String couldNotLoadTheImage(Object error);

  /// No description provided for @cameraIsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera is unavailable right now. {error}'**
  String cameraIsUnavailable(Object error);

  /// No description provided for @couldNotLoadTheVideo.
  ///
  /// In en, this message translates to:
  /// **'Could not load the selected video. {error}'**
  String couldNotLoadTheVideo(Object error);

  /// No description provided for @couldNotOpenThatAudioFile.
  ///
  /// In en, this message translates to:
  /// **'Could not open that audio file. {error}'**
  String couldNotOpenThatAudioFile(Object error);

  /// No description provided for @scheduledCallWith.
  ///
  /// In en, this message translates to:
  /// **'Scheduled call with {name}'**
  String scheduledCallWith(Object name);

  /// No description provided for @notifNewDirectMessages.
  ///
  /// In en, this message translates to:
  /// **'Notifications for new direct messages'**
  String get notifNewDirectMessages;

  /// No description provided for @notifGroupMessages.
  ///
  /// In en, this message translates to:
  /// **'Notifications for group messages'**
  String get notifGroupMessages;

  /// No description provided for @notifIncomingCalls.
  ///
  /// In en, this message translates to:
  /// **'Incoming call notifications'**
  String get notifIncomingCalls;

  /// No description provided for @notifStatusUpdates.
  ///
  /// In en, this message translates to:
  /// **'Notifications about status updates'**
  String get notifStatusUpdates;

  /// No description provided for @notifScheduledReminders.
  ///
  /// In en, this message translates to:
  /// **'Scheduled call reminders'**
  String get notifScheduledReminders;

  /// No description provided for @notifChannelMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get notifChannelMessages;

  /// No description provided for @notifChannelCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get notifChannelCalls;

  /// No description provided for @notifChannelStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get notifChannelStatus;

  /// No description provided for @notifChannelReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get notifChannelReminders;

  /// No description provided for @donTHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get donTHaveAnAccount;

  /// No description provided for @alreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAnAccount;

  /// No description provided for @youCreatedTheGroup.
  ///
  /// In en, this message translates to:
  /// **'You created the group'**
  String get youCreatedTheGroup;

  /// No description provided for @doesImoLIVEHaveEnd.
  ///
  /// In en, this message translates to:
  /// **'Does Imo LIVE have end-to-end encryption?'**
  String get doesImoLIVEHaveEnd;

  /// No description provided for @noAndThisAppDeliberately.
  ///
  /// In en, this message translates to:
  /// **'No — and this app deliberately does not claim it. Your messages travel over an encrypted connection (TLS) to Cloud Firestore, and media goes to Cloudflare R2, but the servers can read them: end-to-end means only the two participants hold the keys, and no key exchange is implemented yet.'**
  String get noAndThisAppDeliberately;

  /// No description provided for @doINeedAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Do I need an account or phone number?'**
  String get doINeedAnAccount;

  /// No description provided for @anAccountYesSignIn.
  ///
  /// In en, this message translates to:
  /// **'An account, yes. Sign in with email, Google or a phone number so your chats and profile can sync and so people can find you. A phone number is just one of the ways someone can look you up, alongside your email, @handle and user id.'**
  String get anAccountYesSignIn;

  /// No description provided for @whereAreMyPhotosAnd.
  ///
  /// In en, this message translates to:
  /// **'Where are my photos and voice notes stored?'**
  String get whereAreMyPhotosAnd;

  /// No description provided for @aCopyStaysInThe.
  ///
  /// In en, this message translates to:
  /// **'A copy stays in the app\'s private folder on this device, split into images, videos, audio, voice notes, documents, profile photos, wallpapers and status media, and it is uploaded to Cloudflare R2 so the recipient can fetch it. Storage and data shows exactly how much space each category uses and lets you clear any of them.'**
  String get aCopyStaysInThe;

  /// No description provided for @willMyMessagesDisappear.
  ///
  /// In en, this message translates to:
  /// **'Will my messages disappear?'**
  String get willMyMessagesDisappear;

  /// No description provided for @onlyIfYouTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Only if you turn on a disappearing-message timer for a chat. Otherwise messages stay until you delete them. The Storage screen has a \"purge expired messages\" action that removes messages whose timer already elapsed.'**
  String get onlyIfYouTurnOn;

  /// No description provided for @howDoIMoveMy.
  ///
  /// In en, this message translates to:
  /// **'How do I move my chats to a new phone?'**
  String get howDoIMoveMy;

  /// No description provided for @signInWithTheSame.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the same account on the new phone and your chats are restored from the cloud. Messages sent from either device appear on both, so nothing has to be exported by hand.'**
  String get signInWithTheSame;

  /// No description provided for @whyCanTILink.
  ///
  /// In en, this message translates to:
  /// **'Why can\'t I link a second device?'**
  String get whyCanTILink;

  /// No description provided for @companionPairingNeedsASession.
  ///
  /// In en, this message translates to:
  /// **'Companion pairing needs a session handshake that has not been built yet. The Linked devices screen shows the device you are signed in on and explains what pairing would do, rather than faking a successful link.'**
  String get companionPairingNeedsASession;

  /// No description provided for @canIUseImoLIVE.
  ///
  /// In en, this message translates to:
  /// **'Can I use Imo LIVE in my own language?'**
  String get canIUseImoLIVE;

  /// No description provided for @yesEnglishAndShipWith.
  ///
  /// In en, this message translates to:
  /// **'Yes — English and বাংলা ship with complete translations. More languages can be added by dropping a new ARB file into lib/l10n and running the localization generator.'**
  String get yesEnglishAndShipWith;

  /// No description provided for @howDoIReportA.
  ///
  /// In en, this message translates to:
  /// **'How do I report a problem?'**
  String get howDoIReportA;

  /// No description provided for @useContactUsBelowReports.
  ///
  /// In en, this message translates to:
  /// **'Use \"Contact us\" below. Reports open in your email app so you can see exactly what is being sent.'**
  String get useContactUsBelowReports;

  /// No description provided for @verifyingASecondFactorIs.
  ///
  /// In en, this message translates to:
  /// **'Verifying a second factor is not implemented yet. The row is present so the setting has an obvious home.'**
  String get verifyingASecondFactorIs;

  /// No description provided for @passkeysAreNotImplementedYet.
  ///
  /// In en, this message translates to:
  /// **'Passkeys are not implemented yet. They will be bound to your account when they are.'**
  String get passkeysAreNotImplementedYet;

  /// No description provided for @devicePairing.
  ///
  /// In en, this message translates to:
  /// **'Device pairing'**
  String get devicePairing;

  /// No description provided for @aLinkedDeviceAuthenticatesAgainst.
  ///
  /// In en, this message translates to:
  /// **'A linked device authenticates against your account and syncs a message history snapshot. Neither step has been built yet. The repository boundary (SettingsRepository.getLinkedDevices / saveLinkedDevices) is already in place, so an implementation plugs in without UI changes.'**
  String get aLinkedDeviceAuthenticatesAgainst;

  /// No description provided for @linkingWithAPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Linking with a phone number'**
  String get linkingWithAPhoneNumber;

  /// No description provided for @allChannels.
  ///
  /// In en, this message translates to:
  /// **'All channels'**
  String get allChannels;

  /// No description provided for @photoPost.
  ///
  /// In en, this message translates to:
  /// **'Photo post'**
  String get photoPost;

  /// No description provided for @textPost.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get textPost;

  /// Shown when a requested channel @handle is already in use and alternatives exist.
  ///
  /// In en, this message translates to:
  /// **'@{username} is taken — try {suggestions}'**
  String usernameTakenWithSuggestions(String username, String suggestions);

  /// Shown when a requested channel @handle is already in use and no alternative could be suggested.
  ///
  /// In en, this message translates to:
  /// **'@{username} is taken'**
  String usernameTaken(String username);

  /// No description provided for @anythingWithABadge.
  ///
  /// In en, this message translates to:
  /// **'Anything with a badge'**
  String get anythingWithABadge;

  /// No description provided for @continueWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Continue with Phone'**
  String get continueWithPhone;

  /// No description provided for @orContinueWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Or continue with phone'**
  String get orContinueWithPhone;

  /// No description provided for @phoneSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Your phone number'**
  String get phoneSignInTitle;

  /// No description provided for @phoneSignInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll use this number to sign you in. No SMS code needed.'**
  String get phoneSignInSubtitle;

  /// No description provided for @loginWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Login with Phone'**
  String get loginWithPhone;

  /// No description provided for @signUpWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Sign up with Phone'**
  String get signUpWithPhone;

  /// No description provided for @searchCountryOrCode.
  ///
  /// In en, this message translates to:
  /// **'Search country or code'**
  String get searchCountryOrCode;

  /// No description provided for @noCountryMatchesSearch.
  ///
  /// In en, this message translates to:
  /// **'No country matches that search'**
  String get noCountryMatchesSearch;

  /// No description provided for @usernameLeaveBlankToGenerate.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to generate one automatically'**
  String get usernameLeaveBlankToGenerate;

  /// No description provided for @pinAtLeastSixDigits.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 digits'**
  String get pinAtLeastSixDigits;

  /// No description provided for @pinStoredSecurely.
  ///
  /// In en, this message translates to:
  /// **'Your PIN is stored securely and is never shown to anyone.'**
  String get pinStoredSecurely;

  /// No description provided for @enterYourPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get enterYourPhoneNumber;

  /// No description provided for @enterAValidPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'That phone number doesn\'t look right'**
  String get enterAValidPhoneNumber;

  /// No description provided for @enterYourFirstName.
  ///
  /// In en, this message translates to:
  /// **'Enter your first name'**
  String get enterYourFirstName;

  /// No description provided for @enterYourLastName.
  ///
  /// In en, this message translates to:
  /// **'Enter your last name'**
  String get enterYourLastName;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @phoneNumberHint.
  ///
  /// In en, this message translates to:
  /// **'1XX XXX XXXX'**
  String get phoneNumberHint;

  /// No description provided for @usernameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use at least 3 letters, numbers, dots or underscores'**
  String get usernameInvalid;

  /// No description provided for @chatMarkedAsRead.
  ///
  /// In en, this message translates to:
  /// **'Marked as read'**
  String get chatMarkedAsRead;

  /// No description provided for @chatMarkedAsUnread.
  ///
  /// In en, this message translates to:
  /// **'Marked as unread'**
  String get chatMarkedAsUnread;

  /// No description provided for @pinChat.
  ///
  /// In en, this message translates to:
  /// **'Pin chat'**
  String get pinChat;

  /// No description provided for @unpinChat.
  ///
  /// In en, this message translates to:
  /// **'Unpin chat'**
  String get unpinChat;

  /// No description provided for @chatPinned.
  ///
  /// In en, this message translates to:
  /// **'Chat pinned'**
  String get chatPinned;

  /// No description provided for @chatUnpinned.
  ///
  /// In en, this message translates to:
  /// **'Chat unpinned'**
  String get chatUnpinned;

  /// No description provided for @unmuteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unmute notifications'**
  String get unmuteNotifications;

  /// No description provided for @notificationsOn.
  ///
  /// In en, this message translates to:
  /// **'Notifications on'**
  String get notificationsOn;

  /// No description provided for @notificationsMuted.
  ///
  /// In en, this message translates to:
  /// **'Notifications muted'**
  String get notificationsMuted;

  /// No description provided for @archiveChat.
  ///
  /// In en, this message translates to:
  /// **'Archive chat'**
  String get archiveChat;

  /// No description provided for @unarchiveChat.
  ///
  /// In en, this message translates to:
  /// **'Unarchive chat'**
  String get unarchiveChat;

  /// No description provided for @chatArchived.
  ///
  /// In en, this message translates to:
  /// **'Chat archived'**
  String get chatArchived;

  /// No description provided for @chatUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Chat unarchived'**
  String get chatUnarchived;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavorites;

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavorites;

  /// No description provided for @emptyChatsUnreadTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get emptyChatsUnreadTitle;

  /// No description provided for @emptyChatsUnreadMessage.
  ///
  /// In en, this message translates to:
  /// **'No unread conversations right now.'**
  String get emptyChatsUnreadMessage;

  /// No description provided for @emptyChatsFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get emptyChatsFavoritesTitle;

  /// No description provided for @emptyChatsFavoritesMessage.
  ///
  /// In en, this message translates to:
  /// **'Add chats to your favorites to find them faster.'**
  String get emptyChatsFavoritesMessage;

  /// No description provided for @emptyChatsGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get emptyChatsGroupsTitle;

  /// No description provided for @emptyChatsGroupsMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a group to chat with several people at once.'**
  String get emptyChatsGroupsMessage;

  /// No description provided for @emptyChatsWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'No work chats'**
  String get emptyChatsWorkTitle;

  /// No description provided for @emptyChatsWorkMessage.
  ///
  /// In en, this message translates to:
  /// **'Work conversations you tag will appear here.'**
  String get emptyChatsWorkMessage;

  /// No description provided for @startAChat.
  ///
  /// In en, this message translates to:
  /// **'Start a chat'**
  String get startAChat;

  /// No description provided for @starredAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to starred'**
  String get starredAdded;

  /// No description provided for @starredRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from starred'**
  String get starredRemoved;

  /// No description provided for @channelApproved.
  ///
  /// In en, this message translates to:
  /// **'Channel approved'**
  String get channelApproved;

  /// No description provided for @applicationRejected.
  ///
  /// In en, this message translates to:
  /// **'Application rejected'**
  String get applicationRejected;

  /// No description provided for @couldNotLoadAnAd.
  ///
  /// In en, this message translates to:
  /// **'Could not load an ad'**
  String get couldNotLoadAnAd;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable.'**
  String get locationUnavailable;

  /// No description provided for @appLockDisabled.
  ///
  /// In en, this message translates to:
  /// **'App lock disabled'**
  String get appLockDisabled;

  /// No description provided for @notAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get notAvailableYet;

  /// A duration in whole hours, e.g. 2 hours.
  ///
  /// In en, this message translates to:
  /// **'{n} hours'**
  String hoursCount(int n);

  /// A duration in whole minutes.
  ///
  /// In en, this message translates to:
  /// **'{n} minutes'**
  String minutesCount(int n);

  /// A duration in whole seconds.
  ///
  /// In en, this message translates to:
  /// **'{n} seconds'**
  String secondsCount(int n);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
