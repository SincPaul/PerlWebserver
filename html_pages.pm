package html_pages;

use strict;
use warnings;

use HTML_PAGES::About::about_html;

use HTML_PAGES::Admin::admin_html;

use HTML_PAGES::Admin::Announcements::get_blog_announcements_manage;
use HTML_PAGES::Admin::Announcements::get_announcement_edit;
use HTML_PAGES::Admin::Announcements::get_announcement_create;

use HTML_PAGES::Admin::Users::admin_user_html;
use HTML_PAGES::Admin::Users::get_admin_edit_user;
use HTML_PAGES::Admin::Users::get_admin_ban_user;
use HTML_PAGES::Admin::Users::get_admin_view_user;
use HTML_PAGES::Admin::Users::get_admin_delete_user;

use HTML_PAGES::Admin::UpdateLog::get_update_log_manage;
use HTML_PAGES::Admin::UpdateLog::get_admin_update_log_add;
use HTML_PAGES::Admin::UpdateLog::get_admin_update_log_edit;
use HTML_PAGES::Admin::UpdateLog::get_admin_update_log_delete;

use HTML_PAGES::Admin::GameLauncher::get_admin_game_launcher_html;
use HTML_PAGES::Admin::GameLauncher::get_admin_game_launcher_add;
use HTML_PAGES::Admin::GameLauncher::get_admin_game_launcher_add_new;
use HTML_PAGES::Admin::GameLauncher::get_admin_game_edit;

use HTML_PAGES::Blog::get_blog;
use HTML_PAGES::Blog::get_blog_view;
use HTML_PAGES::Blog::get_blog_create;


use HTML_PAGES::Calender::get_calender_year;
use HTML_PAGES::Calender::get_calender_month;


use HTML_PAGES::Email::get_email_not_verified;
use HTML_PAGES::Email::get_require_email;
use HTML_PAGES::Email::unlinked_email_html;
use HTML_PAGES::Email::get_change_email;


use HTML_PAGES::Gameroom::get_gameroom;

use HTML_PAGES::Gameroom::Memory::get_memory;
use HTML_PAGES::Gameroom::Memory::get_memory_alone;
use HTML_PAGES::Gameroom::Memory::get_memory_2player;
use HTML_PAGES::Gameroom::Memory::get_memory_2player_waiting;
use HTML_PAGES::Gameroom::Memory::get_memory_end;
use HTML_PAGES::Gameroom::Memory::get_memory_spectate;


use HTML_PAGES::html_structure;


use HTML_PAGES::index_html;


use HTML_PAGES::Login::login_html;
use HTML_PAGES::Login::logined_html;


use HTML_PAGES::Logout::logout_html;


use HTML_PAGES::Profile::profile_html;

use HTML_PAGES::Profile::get_profile_ploud;
use HTML_PAGES::Profile::get_profile_ploud_upload;
use HTML_PAGES::Profile::get_profile_ploud_upgrade;
use HTML_PAGES::Profile::get_profile_ploud_upgrade_rank;


use HTML_PAGES::Register::register_html;
use HTML_PAGES::Register::registered_html;


use HTML_PAGES::Support::User::get_user_main_support_page;
use HTML_PAGES::Support::get_choose_request_support_page;

use HTML_PAGES::Streaming::streaming_html;
use HTML_PAGES::Streaming::streaming_upload;
use HTML_PAGES::Streaming::streaming_video;
use HTML_PAGES::Streaming::streaming_channel;
use HTML_PAGES::Streaming::streaming_manage_channel;


use HTML_PAGES::shutdown_html;


use HTML_PAGES::UpdateLog::update_log_html;


# use User::Utils::utils;

use lib 'Webserver';
use Utils::DataUtils::Important::Devs::dev_utils;
use Utils::DataUtils::Important::Devs::hardware_devs;
use Utils::DataUtils::Important::no_upload;

use Utils::DataUtils::blog_utils;
use Utils::DataUtils::body_utils;
use Utils::DataUtils::calender_utils;
use Utils::DataUtils::chat_utils;
use Utils::DataUtils::channel_utils;
use Utils::DataUtils::csharp_game;
use Utils::DataUtils::connection_utils;
use Utils::DataUtils::friend_utils;
use Utils::DataUtils::language_utils;
use Utils::DataUtils::memory_utils;
use Utils::DataUtils::request_utils;
use Utils::DataUtils::upload_utils;
use Utils::DataUtils::user_utils;
use Utils::DataUtils::admin_utils;
use Utils::DataUtils::http_utils;
use Utils::DataUtils::https_utils;
use Utils::DataUtils::github_utils;

use Utils::DataUtils::User::register_user;
use Utils::DataUtils::User::login_user;
use Utils::DataUtils::User::logout_user;
use Utils::DataUtils::User::ip_utils;
use Utils::DataUtils::User::cookie_utils;
use Utils::DataUtils::User::email_utils;
use Utils::DataUtils::User::get_users;


use Utils::DataUtils::update_log;

use Utils::DataUtils::encryption_utils;

use Utils::DataUtils::Game::game_utils;
use Utils::DataUtils::Game::Memory::memory_game_utils;

use Utils::DataUtils::support_utils;

use Utils::DataUtils::video_utils;
use Utils::DataUtils::image_utils;


use Utils::StyleUtils::html_utils;
use Utils::StyleUtils::css_utils;
use Utils::StyleUtils::scheme_utils;

use Utils::HtmlPagesUtils::Blog::get_blog_pages;
use Utils::HtmlPagesUtils::Blog::post_blog_pages;

use Utils::HtmlPagesUtils::Friends::get_friends;
use Utils::HtmlPagesUtils::Friends::post_friends;

use Utils::HtmlPagesUtils::Gameroom::get_gameroom_page;
use Utils::HtmlPagesUtils::Gameroom::Memory::get_memory_pages;

use Utils::LoadStuffUtils::load_fonts;
use Utils::LoadStuffUtils::load_js;

use Utils::HtmlPagesUtils::Profile::get_profile_pages;
use Utils::HtmlPagesUtils::Profile::post_profile_pages;

use Utils::HtmlPagesUtils::Preferences::post_preferences;

use Utils::HtmlPagesUtils::Server::get_server_ip;

use Utils::HtmlPagesUtils::Admin::get_admin_page;
use Utils::HtmlPagesUtils::Admin::Users::post_admin_users_pages;
use Utils::HtmlPagesUtils::Admin::Users::get_admin_users_pages;
use Utils::HtmlPagesUtils::Admin::UpdateLog::get_admin_update_log_manage;
use Utils::HtmlPagesUtils::Admin::UpdateLog::post_admin_update_log_manage;
use Utils::HtmlPagesUtils::Admin::GameLauncher::get_admin_game_launcher;
use Utils::HtmlPagesUtils::Admin::GameLauncher::post_admin_game_launcher;

use Utils::HtmlPagesUtils::Calender::get_calender_pages;

use Utils::HtmlPagesUtils::User::get_operation_finished_pages;

use Utils::HtmlPagesUtils::Index::get_index_page;

use Utils::HtmlPagesUtils::Register::get_register_page;
use Utils::HtmlPagesUtils::Login::get_login_page;

use Utils::HtmlPagesUtils::Shutdown::get_shutdown_page;

use Utils::HtmlPagesUtils::Favicon::get_favicon;

use Utils::HtmlPagesUtils::Important::Devs::post_contact_devs;

use Utils::HtmlPagesUtils::About::get_about_page;

use Utils::HtmlPagesUtils::UpdateLog::get_update_log_page;

use Utils::HtmlPagesUtils::Support::get_support_pages;

use Utils::HtmlPagesUtils::Streaming::get_streaming_pages;
use Utils::HtmlPagesUtils::Streaming::post_streaming_pages;

# use Utils::SMTP_SERVER::smtp_utils;
use Utils::SMTP_SERVER::smtp_utils2;
use Utils::SMTP_SERVER::smtp_send;

use Utils::WebSocketUtils::friend_websocket;
use Utils::WebSocketUtils::chat_websocket;
use Utils::WebSocketUtils::websocket_utils;
1;