<?php
/**
 * OnePager - Theme Functions
 *
 * Main functions file for the OnePager custom WordPress theme.
 * Handles theme setup, asset enqueueing, custom nav walker, and helper functions.
 *
 * @package OnePager
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

define( 'OP_THEME_VERSION', '1.0.0' );
define( 'OP_THEME_PATH', get_template_directory() );
define( 'OP_THEME_URI', get_template_directory_uri() );

function op_theme_setup() {
    add_theme_support( 'title-tag' );
    add_theme_support( 'post-thumbnails' );
    add_theme_support( 'custom-logo', array(
        'height'      => 80,
        'width'       => 250,
        'flex-height' => true,
        'flex-width'  => true,
    ) );
    add_theme_support( 'html5', array(
        'search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script',
    ) );
    register_nav_menus( array(
        'primary' => esc_html__( 'Primary Menu', 'onepager' ),
    ) );
}
add_action( 'after_setup_theme', 'op_theme_setup' );

function op_enqueue_assets() {
    wp_enqueue_style( 'op-google-fonts', 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Playfair+Display:wght@400;500;600;700&display=swap', array(), null );
    wp_enqueue_style( 'op-font-awesome', 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css', array(), '6.5.1' );
    wp_enqueue_style( 'op-theme-style', get_stylesheet_uri(), array( 'op-google-fonts', 'op-font-awesome' ), OP_THEME_VERSION );
    wp_enqueue_script( 'op-theme-script', OP_THEME_URI . '/assets/js/script.js', array( 'jquery' ), OP_THEME_VERSION, true );
}
add_action( 'wp_enqueue_scripts', 'op_enqueue_assets' );

require_once get_template_directory() . '/inc/post-types.php';
require_once get_template_directory() . '/inc/customizer.php';
require_once get_template_directory() . '/inc/theme-setup.php';

function op_flag_last_menu_item( $sorted_menu_items, $args ) {
    if ( empty( $args->theme_location ) || 'primary' !== $args->theme_location ) {
        return $sorted_menu_items;
    }
    $last_top_level_key = null;
    foreach ( $sorted_menu_items as $key => $item ) {
        if ( 0 === (int) $item->menu_item_parent ) {
            $last_top_level_key = $key;
        }
    }
    if ( null !== $last_top_level_key ) {
        $sorted_menu_items[ $last_top_level_key ]->classes[] = 'op-cta-item';
    }
    return $sorted_menu_items;
}
add_filter( 'wp_nav_menu_objects', 'op_flag_last_menu_item', 10, 2 );

class OP_Nav_Walker extends Walker_Nav_Menu {
    public function start_el( &$output, $item, $depth = 0, $args = null, $id = 0 ) {
        $classes = 'nav-link';
        if ( ! empty( $item->classes ) && is_array( $item->classes ) && in_array( 'op-cta-item', $item->classes, true ) ) {
            $classes .= ' nav-cta';
        }
        $url = ! empty( $item->url ) ? esc_url( $item->url ) : '';
        $output .= '<li>';
        $output .= '<a href="' . $url . '" class="' . esc_attr( $classes ) . '">';
        $output .= esc_html( $item->title );
        $output .= '</a>';
    }
    public function end_el( &$output, $item, $depth = 0, $args = null ) {
        $output .= '</li>';
    }
}

function op_get_option( $key, $default = '' ) {
    return get_theme_mod( $key, $default );
}

/**
 * Return the list of available Font Awesome icon choices for Customizer dropdowns.
 */
function op_get_icon_choices() {
    return array(
        '' => '— No icon —',

        // Health & Medical
        'fa-user-md'              => 'Doctor (fa-user-md)',
        'fa-stethoscope'          => 'Stethoscope (fa-stethoscope)',
        'fa-heartbeat'            => 'Heartbeat (fa-heartbeat)',
        'fa-heart'                => 'Heart (fa-heart)',
        'fa-file-medical'         => 'Medical file (fa-file-medical)',
        'fa-hand-holding-medical' => 'Medical hand (fa-hand-holding-medical)',
        'fa-notes-medical'        => 'Medical notes (fa-notes-medical)',
        'fa-hospital'             => 'Hospital (fa-hospital)',
        'fa-medkit'               => 'First aid kit (fa-medkit)',
        'fa-ambulance'            => 'Ambulance (fa-ambulance)',
        'fa-syringe'              => 'Syringe (fa-syringe)',
        'fa-pills'                => 'Pills (fa-pills)',
        'fa-dna'                  => 'DNA (fa-dna)',
        'fa-microscope'           => 'Microscope (fa-microscope)',
        'fa-thermometer-half'     => 'Thermometer (fa-thermometer-half)',
        'fa-wheelchair'           => 'Wheelchair (fa-wheelchair)',
        'fa-tooth'                => 'Tooth (fa-tooth)',

        // Body & Anatomy
        'fa-bone'                 => 'Bone (fa-bone)',
        'fa-lungs'                => 'Lungs (fa-lungs)',
        'fa-brain'                => 'Brain (fa-brain)',

        // People & Family
        'fa-baby'                 => 'Baby (fa-baby)',
        'fa-female'               => 'Female (fa-female)',
        'fa-male'                 => 'Male (fa-male)',
        'fa-child'                => 'Child (fa-child)',
        'fa-user'                 => 'Person (fa-user)',
        'fa-user-friends'         => 'Friends (fa-user-friends)',
        'fa-user-tie'             => 'Business person (fa-user-tie)',
        'fa-users'                => 'Group (fa-users)',

        // Activity & Movement
        'fa-running'              => 'Running (fa-running)',
        'fa-walking'              => 'Walking (fa-walking)',
        'fa-bicycle'              => 'Bicycle (fa-bicycle)',
        'fa-dumbbell'             => 'Weights (fa-dumbbell)',
        'fa-shoe-prints'          => 'Footprints (fa-shoe-prints)',

        // Hands & Touch
        'fa-hand-paper'           => 'Open hand (fa-hand-paper)',
        'fa-hand-sparkles'        => 'Hand sparkles (fa-hand-sparkles)',
        'fa-hands'                => 'Hands (fa-hands)',
        'fa-hands-helping'        => 'Helping hands (fa-hands-helping)',
        'fa-handshake'            => 'Handshake (fa-handshake)',
        'fa-hand-holding-heart'   => 'Hand with heart (fa-hand-holding-heart)',

        // Office & Work
        'fa-laptop'               => 'Laptop (fa-laptop)',
        'fa-desktop'              => 'Desktop (fa-desktop)',
        'fa-couch'                => 'Couch (fa-couch)',
        'fa-chair'                => 'Chair (fa-chair)',
        'fa-bed'                  => 'Bed (fa-bed)',

        // Nature
        'fa-wind'                 => 'Wind (fa-wind)',
        'fa-leaf'                 => 'Leaf (fa-leaf)',
        'fa-seedling'             => 'Seedling (fa-seedling)',
        'fa-tree'                 => 'Tree (fa-tree)',
        'fa-sun'                  => 'Sun (fa-sun)',
        'fa-fire'                 => 'Fire (fa-fire)',
        'fa-bolt'                 => 'Lightning (fa-bolt)',
        'fa-water'                => 'Water (fa-water)',

        // Business & Finance
        'fa-building'             => 'Building (fa-building)',
        'fa-briefcase'            => 'Briefcase (fa-briefcase)',
        'fa-chart-line'           => 'Line chart (fa-chart-line)',
        'fa-chart-bar'            => 'Bar chart (fa-chart-bar)',
        'fa-chart-pie'            => 'Pie chart (fa-chart-pie)',
        'fa-piggy-bank'           => 'Piggy bank (fa-piggy-bank)',
        'fa-receipt'              => 'Receipt (fa-receipt)',
        'fa-percentage'           => 'Percentage (fa-percentage)',
        'fa-calculator'           => 'Calculator (fa-calculator)',
        'fa-file-invoice-dollar'  => 'Invoice (fa-file-invoice-dollar)',
        'fa-money-bill-wave'      => 'Money (fa-money-bill-wave)',
        'fa-coins'                => 'Coins (fa-coins)',
        'fa-wallet'               => 'Wallet (fa-wallet)',
        'fa-credit-card'          => 'Credit card (fa-credit-card)',
        'fa-store'                => 'Store (fa-store)',
        'fa-industry'             => 'Industry (fa-industry)',

        // Communication
        'fa-phone'                => 'Phone (fa-phone)',
        'fa-phone-alt'            => 'Phone alt (fa-phone-alt)',
        'fa-envelope'             => 'Email (fa-envelope)',
        'fa-paper-plane'          => 'Paper plane (fa-paper-plane)',
        'fa-comments'             => 'Chat (fa-comments)',
        'fa-comment'              => 'Comment (fa-comment)',
        'fa-bullhorn'             => 'Megaphone (fa-bullhorn)',

        // Location & Time
        'fa-map-marker-alt'       => 'Map marker (fa-map-marker-alt)',
        'fa-map'                  => 'Map (fa-map)',
        'fa-compass'              => 'Compass (fa-compass)',
        'fa-globe'                => 'Globe (fa-globe)',
        'fa-clock'                => 'Clock (fa-clock)',
        'fa-calendar'             => 'Calendar (fa-calendar)',
        'fa-calendar-check'       => 'Calendar check (fa-calendar-check)',
        'fa-hourglass-half'       => 'Hourglass (fa-hourglass-half)',
        'fa-stopwatch'            => 'Stopwatch (fa-stopwatch)',

        // Education
        'fa-graduation-cap'       => 'Graduation cap (fa-graduation-cap)',
        'fa-book'                 => 'Book (fa-book)',
        'fa-book-open'            => 'Open book (fa-book-open)',
        'fa-university'           => 'University (fa-university)',
        'fa-chalkboard-teacher'   => 'Teacher (fa-chalkboard-teacher)',
        'fa-user-graduate'        => 'Graduate (fa-user-graduate)',

        // Security & Trust
        'fa-shield-alt'           => 'Shield (fa-shield-alt)',
        'fa-lock'                 => 'Lock (fa-lock)',
        'fa-certificate'          => 'Certificate (fa-certificate)',
        'fa-award'                => 'Award (fa-award)',
        'fa-medal'                => 'Medal (fa-medal)',
        'fa-trophy'               => 'Trophy (fa-trophy)',
        'fa-star'                 => 'Star (fa-star)',
        'fa-crown'                => 'Crown (fa-crown)',
        'fa-gem'                  => 'Gem (fa-gem)',

        // Status & Indicators
        'fa-check'                => 'Check (fa-check)',
        'fa-check-circle'         => 'Check circle (fa-check-circle)',
        'fa-check-double'         => 'Double check (fa-check-double)',
        'fa-times'                => 'Times (fa-times)',
        'fa-plus'                 => 'Plus (fa-plus)',
        'fa-plus-circle'          => 'Plus circle (fa-plus-circle)',
        'fa-info-circle'          => 'Info circle (fa-info-circle)',
        'fa-question-circle'      => 'Question circle (fa-question-circle)',
        'fa-exclamation-triangle'  => 'Warning triangle (fa-exclamation-triangle)',
        'fa-bell'                 => 'Bell (fa-bell)',

        // Arrows & Navigation
        'fa-arrow-down'           => 'Arrow down (fa-arrow-down)',
        'fa-arrow-up'             => 'Arrow up (fa-arrow-up)',
        'fa-arrow-right'          => 'Arrow right (fa-arrow-right)',
        'fa-arrow-left'           => 'Arrow left (fa-arrow-left)',
        'fa-chevron-down'         => 'Chevron down (fa-chevron-down)',
        'fa-chevron-right'        => 'Chevron right (fa-chevron-right)',
        'fa-external-link-alt'    => 'External link (fa-external-link-alt)',

        // General
        'fa-home'                 => 'Home (fa-home)',
        'fa-cog'                  => 'Gear (fa-cog)',
        'fa-cogs'                 => 'Gears (fa-cogs)',
        'fa-wrench'               => 'Wrench (fa-wrench)',
        'fa-tools'                => 'Tools (fa-tools)',
        'fa-lightbulb'            => 'Lightbulb (fa-lightbulb)',
        'fa-link'                 => 'Link (fa-link)',
        'fa-thumbs-up'            => 'Thumbs up (fa-thumbs-up)',
        'fa-smile'                => 'Smile (fa-smile)',
        'fa-search'               => 'Search (fa-search)',
        'fa-eye'                  => 'Eye (fa-eye)',
        'fa-key'                  => 'Key (fa-key)',
        'fa-flag'                 => 'Flag (fa-flag)',
        'fa-tags'                 => 'Tags (fa-tags)',
        'fa-clipboard-list'       => 'Checklist (fa-clipboard-list)',
        'fa-tasks'                => 'Tasks (fa-tasks)',
        'fa-list'                 => 'List (fa-list)',
        'fa-quote-left'           => 'Quote (fa-quote-left)',
        'fa-paint-brush'          => 'Paint brush (fa-paint-brush)',
        'fa-camera'               => 'Camera (fa-camera)',
        'fa-video'                => 'Video (fa-video)',
        'fa-coffee'               => 'Coffee (fa-coffee)',
        'fa-car'                  => 'Car (fa-car)',
        'fa-parking'              => 'Parking (fa-parking)',
        'fa-recycle'              => 'Recycle (fa-recycle)',
        'fa-spa'                  => 'Spa (fa-spa)',
        'fa-yin-yang'             => 'Yin-Yang (fa-yin-yang)',
        'fa-balance-scale'        => 'Balance scale (fa-balance-scale)',
    );
}
