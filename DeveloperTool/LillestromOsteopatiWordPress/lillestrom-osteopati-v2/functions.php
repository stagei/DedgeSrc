<?php
/**
 * Lillestrøm Osteopati - Theme Functions
 *
 * Main functions file for the Lillestrøm Osteopati custom WordPress theme.
 * Handles theme setup, asset enqueueing, custom nav walker, and helper functions.
 *
 * @package Lillestrom_Osteopati
 * @since   1.0.0
 */

// Prevent direct access.
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/*--------------------------------------------------------------
 * 1. Theme Constants
 *--------------------------------------------------------------*/

define( 'LO_THEME_VERSION', '2.1.0' );
define( 'LO_THEME_PATH', get_template_directory() );
define( 'LO_THEME_URI', get_template_directory_uri() );

/*--------------------------------------------------------------
 * 2. Theme Setup
 *--------------------------------------------------------------*/

/**
 * Sets up theme defaults and registers support for various WordPress features.
 *
 * @since 1.0.0
 */
function lo_theme_setup() {
    // Let WordPress manage the document title.
    add_theme_support( 'title-tag' );

    // Enable support for post thumbnails on posts and pages.
    add_theme_support( 'post-thumbnails' );

    // Enable support for a custom logo.
    add_theme_support( 'custom-logo', array(
        'height'      => 80,
        'width'       => 250,
        'flex-height' => true,
        'flex-width'  => true,
    ) );

    // Switch default core markup to output valid HTML5.
    add_theme_support( 'html5', array(
        'search-form',
        'comment-form',
        'comment-list',
        'gallery',
        'caption',
        'style',
        'script',
    ) );

    // Register navigation menus.
    register_nav_menus( array(
        'primary' => esc_html__( 'Hovedmeny', 'lillestrom-osteopati-v2' ),
    ) );
}
add_action( 'after_setup_theme', 'lo_theme_setup' );

/*--------------------------------------------------------------
 * 3. Enqueue Scripts & Styles
 *--------------------------------------------------------------*/

/**
 * Enqueue front-end scripts and styles.
 *
 * @since 1.0.0
 */
function lo_enqueue_assets() {
    // Google Fonts: Inter (300-700) + Playfair Display (400-700).
    wp_enqueue_style(
        'lo-google-fonts',
        'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Playfair+Display:wght@400;500;600;700&display=swap',
        array(),
        null
    );

    // Font Awesome 6.5.1 from cdnjs.
    wp_enqueue_style(
        'lo-font-awesome',
        'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css',
        array(),
        '6.5.1'
    );

    // Theme main stylesheet (style.css).
    wp_enqueue_style(
        'lo-theme-style',
        get_stylesheet_uri(),
        array( 'lo-google-fonts', 'lo-font-awesome' ),
        LO_THEME_VERSION
    );

    // Theme main script (assets/js/script.js) — loaded in footer with jQuery dependency.
    wp_enqueue_script(
        'lo-theme-script',
        LO_THEME_URI . '/assets/js/script.js',
        array( 'jquery' ),
        LO_THEME_VERSION,
        true
    );
}
add_action( 'wp_enqueue_scripts', 'lo_enqueue_assets' );

/*--------------------------------------------------------------
 * 4. Include Files
 *--------------------------------------------------------------*/

// Custom post types and taxonomies.
require_once get_template_directory() . '/inc/post-types.php';

// Customizer settings and controls.
require_once get_template_directory() . '/inc/customizer.php';

// Additional theme setup (widgets, sidebars, etc.).
require_once get_template_directory() . '/inc/theme-setup.php';

/*--------------------------------------------------------------
 * 5. Custom Nav Walker
 *--------------------------------------------------------------*/

/**
 * Flag the last top-level item in the primary menu with a custom CSS class.
 *
 * This filter runs before the walker processes menu items, allowing the
 * walker to reliably detect the last item via its classes array.
 *
 * @param array    $sorted_menu_items The sorted menu items.
 * @param stdClass $args              An object of wp_nav_menu() arguments.
 * @return array
 */
function lo_flag_last_menu_item( $sorted_menu_items, $args ) {
    if ( empty( $args->theme_location ) || 'primary' !== $args->theme_location ) {
        return $sorted_menu_items;
    }

    // Find the last top-level item (menu_item_parent == 0).
    $last_top_level_key = null;
    foreach ( $sorted_menu_items as $key => $item ) {
        if ( 0 === (int) $item->menu_item_parent ) {
            $last_top_level_key = $key;
        }
    }

    if ( null !== $last_top_level_key ) {
        $sorted_menu_items[ $last_top_level_key ]->classes[] = 'lo-cta-item';
    }

    return $sorted_menu_items;
}
add_filter( 'wp_nav_menu_objects', 'lo_flag_last_menu_item', 10, 2 );

/**
 * Custom navigation walker for the Lillestrøm Osteopati theme.
 *
 * Outputs list items with "nav-link" class on anchor tags.
 * The last menu item (flagged with "lo-cta-item" class) receives
 * an additional "nav-cta" class on its anchor.
 *
 * @since 1.0.0
 */
class LO_Nav_Walker extends Walker_Nav_Menu {

    /**
     * Starts the element output.
     *
     * @param string   $output Used to append additional content (passed by reference).
     * @param WP_Post  $item   Menu item data object.
     * @param int      $depth  Depth of menu item.
     * @param stdClass $args   An object of wp_nav_menu() arguments.
     * @param int      $id     Current item ID.
     */
    public function start_el( &$output, $item, $depth = 0, $args = null, $id = 0 ) {
        // Build anchor classes.
        $classes = 'nav-link';

        // Check if this item was flagged as the CTA (last top-level item).
        if ( ! empty( $item->classes ) && is_array( $item->classes ) && in_array( 'lo-cta-item', $item->classes, true ) ) {
            $classes .= ' nav-cta';
        }

        // Build the menu item URL.
        $url = ! empty( $item->url ) ? esc_url( $item->url ) : '';

        // Open the list item.
        $output .= '<li>';

        // Build the anchor tag.
        $output .= '<a href="' . $url . '" class="' . esc_attr( $classes ) . '">';
        $output .= esc_html( $item->title );
        $output .= '</a>';
    }

    /**
     * Ends the element output.
     *
     * @param string   $output Used to append additional content (passed by reference).
     * @param WP_Post  $item   Menu item data object.
     * @param int      $depth  Depth of menu item.
     * @param stdClass $args   An object of wp_nav_menu() arguments.
     */
    public function end_el( &$output, $item, $depth = 0, $args = null ) {
        $output .= '</li>';
    }
}

/*--------------------------------------------------------------
 * 6. Helper Functions
 *--------------------------------------------------------------*/

/**
 * Retrieve a theme Customizer option.
 *
 * Wrapper around get_theme_mod() for convenient access to Customizer values.
 *
 * @since 1.0.0
 *
 * @param  string $key     The Customizer setting key.
 * @param  mixed  $default Default value if the setting is not found.
 * @return mixed           The Customizer setting value or default.
 */
function lo_get_option( $key, $default = '' ) {
    return get_theme_mod( $key, $default );
}

/**
 * Return the list of available Font Awesome icon choices for Customizer dropdowns.
 *
 * Organized by category with Norwegian labels. Includes every icon
 * used in the original HTML/JS site plus useful additions for
 * healthcare, business, and general UI.
 *
 * @since 2.1.0
 * @return array Associative array of 'fa-class' => 'Label'.
 */
function lo_get_icon_choices() {
    return array(
        '' => '— Ingen ikon —',

        // ── Helse & Medisin ──────────────────────────────
        'fa-user-md'              => 'Lege / Helsepersonell (fa-user-md)',
        'fa-stethoscope'          => 'Stetoskop (fa-stethoscope)',
        'fa-heartbeat'            => 'Hjerteslag (fa-heartbeat)',
        'fa-heart'                => 'Hjerte (fa-heart)',
        'fa-file-medical'         => 'Medisinsk fil (fa-file-medical)',
        'fa-hand-holding-medical' => 'Hånd med medisin (fa-hand-holding-medical)',
        'fa-notes-medical'        => 'Medisinske notater (fa-notes-medical)',
        'fa-book-medical'         => 'Medisinsk bok (fa-book-medical)',
        'fa-hospital'             => 'Sykehus (fa-hospital)',
        'fa-clinic-medical'       => 'Klinikk (fa-clinic-medical)',
        'fa-medkit'               => 'Førstehjelpskoffert (fa-medkit)',
        'fa-first-aid'            => 'Førstehjelp (fa-first-aid)',
        'fa-ambulance'            => 'Ambulanse (fa-ambulance)',
        'fa-syringe'              => 'Sprøyte (fa-syringe)',
        'fa-pills'                => 'Piller (fa-pills)',
        'fa-capsules'             => 'Kapsler (fa-capsules)',
        'fa-x-ray'                => 'Røntgen (fa-x-ray)',
        'fa-dna'                  => 'DNA (fa-dna)',
        'fa-microscope'           => 'Mikroskop (fa-microscope)',
        'fa-thermometer-half'     => 'Termometer (fa-thermometer-half)',
        'fa-procedures'           => 'Behandlingsseng (fa-procedures)',
        'fa-wheelchair'           => 'Rullestol (fa-wheelchair)',
        'fa-head-side-virus'      => 'Hode med smerter (fa-head-side-virus)',
        'fa-head-side-cough'      => 'Hode med hoste (fa-head-side-cough)',
        'fa-head-side-mask'       => 'Hode med maske (fa-head-side-mask)',
        'fa-disease'              => 'Sykdom (fa-disease)',
        'fa-band-aid'             => 'Plaster (fa-band-aid)',
        'fa-tooth'                => 'Tann (fa-tooth)',

        // ── Kropp & Anatomi ──────────────────────────────
        'fa-bone'                 => 'Skjelett / Ben (fa-bone)',
        'fa-lungs'                => 'Lunger (fa-lungs)',
        'fa-brain'                => 'Hjerne (fa-brain)',
        'fa-stomach'              => 'Mage (fa-stomach)',

        // ── Mennesker & Familie ──────────────────────────
        'fa-baby'                 => 'Baby / Spedbarn (fa-baby)',
        'fa-baby-carriage'        => 'Barnevogn (fa-baby-carriage)',
        'fa-female'               => 'Kvinne / Graviditet (fa-female)',
        'fa-male'                 => 'Mann (fa-male)',
        'fa-child'                => 'Barn (fa-child)',
        'fa-user'                 => 'Person (fa-user)',
        'fa-user-friends'         => 'Venner (fa-user-friends)',
        'fa-user-tie'             => 'Person med slips (fa-user-tie)',
        'fa-users'                => 'Gruppe (fa-users)',
        'fa-people-arrows'        => 'Sosial avstand (fa-people-arrows)',

        // ── Aktivitet & Bevegelse ────────────────────────
        'fa-running'              => 'Løping / Idrett (fa-running)',
        'fa-walking'              => 'Gange (fa-walking)',
        'fa-bicycle'              => 'Sykkel (fa-bicycle)',
        'fa-swimmer'              => 'Svømming (fa-swimmer)',
        'fa-dumbbell'             => 'Vekter / Styrke (fa-dumbbell)',
        'fa-shoe-prints'          => 'Fotavtrykk (fa-shoe-prints)',

        // ── Hender & Berøring ────────────────────────────
        'fa-hand-paper'           => 'Åpen hånd (fa-hand-paper)',
        'fa-hand-sparkles'        => 'Hånd med gnist (fa-hand-sparkles)',
        'fa-hands'                => 'Hender (fa-hands)',
        'fa-hands-helping'        => 'Hjelpende hender (fa-hands-helping)',
        'fa-handshake'            => 'Håndtrykk (fa-handshake)',
        'fa-fist-raised'          => 'Knyttneve (fa-fist-raised)',
        'fa-hand-holding-heart'   => 'Hånd med hjerte (fa-hand-holding-heart)',
        'fa-praying-hands'        => 'Foldede hender (fa-praying-hands)',

        // ── Kontor & Hverdag ─────────────────────────────
        'fa-laptop'               => 'Laptop / Kontor (fa-laptop)',
        'fa-desktop'              => 'Skjerm (fa-desktop)',
        'fa-couch'                => 'Sofa / Hvile (fa-couch)',
        'fa-chair'                => 'Stol (fa-chair)',
        'fa-bed'                  => 'Seng (fa-bed)',

        // ── Natur & Vær ─────────────────────────────────
        'fa-wind'                 => 'Vind / Pust (fa-wind)',
        'fa-leaf'                 => 'Blad / Natur (fa-leaf)',
        'fa-seedling'             => 'Spire (fa-seedling)',
        'fa-tree'                 => 'Tre (fa-tree)',
        'fa-sun'                  => 'Sol (fa-sun)',
        'fa-cloud'                => 'Sky (fa-cloud)',
        'fa-fire'                 => 'Flamme (fa-fire)',
        'fa-bolt'                 => 'Lyn (fa-bolt)',
        'fa-water'                => 'Vann (fa-water)',
        'fa-snowflake'            => 'Snøfnugg (fa-snowflake)',

        // ── Bedrift & Økonomi ────────────────────────────
        'fa-building'             => 'Bygning (fa-building)',
        'fa-briefcase'            => 'Koffert (fa-briefcase)',
        'fa-chart-line'           => 'Linjediagram (fa-chart-line)',
        'fa-chart-bar'            => 'Stolpediagram (fa-chart-bar)',
        'fa-chart-pie'            => 'Kakediagram (fa-chart-pie)',
        'fa-chart-area'           => 'Arealgraf (fa-chart-area)',
        'fa-piggy-bank'           => 'Sparegris (fa-piggy-bank)',
        'fa-receipt'              => 'Kvittering (fa-receipt)',
        'fa-percentage'           => 'Prosent (fa-percentage)',
        'fa-calculator'           => 'Kalkulator (fa-calculator)',
        'fa-file-invoice-dollar'  => 'Faktura (fa-file-invoice-dollar)',
        'fa-money-bill-wave'      => 'Pengeseddel (fa-money-bill-wave)',
        'fa-coins'                => 'Mynter (fa-coins)',
        'fa-wallet'               => 'Lommebok (fa-wallet)',
        'fa-credit-card'          => 'Kredittkort (fa-credit-card)',
        'fa-store'                => 'Butikk (fa-store)',
        'fa-industry'             => 'Industri (fa-industry)',

        // ── Kommunikasjon ────────────────────────────────
        'fa-phone'                => 'Telefon (fa-phone)',
        'fa-phone-alt'            => 'Telefon (alt) (fa-phone-alt)',
        'fa-envelope'             => 'Konvolutt / E-post (fa-envelope)',
        'fa-paper-plane'          => 'Papirfly / Send (fa-paper-plane)',
        'fa-comments'             => 'Chatbobler (fa-comments)',
        'fa-comment'              => 'Kommentar (fa-comment)',
        'fa-comment-medical'      => 'Medisinsk kommentar (fa-comment-medical)',
        'fa-at'                   => 'Alfakrøll (fa-at)',
        'fa-inbox'                => 'Innboks (fa-inbox)',
        'fa-bullhorn'             => 'Megafon (fa-bullhorn)',

        // ── Sted & Tid ──────────────────────────────────
        'fa-map-marker-alt'       => 'Kartmarkør (fa-map-marker-alt)',
        'fa-map'                  => 'Kart (fa-map)',
        'fa-map-signs'            => 'Veiskilt (fa-map-signs)',
        'fa-compass'              => 'Kompass (fa-compass)',
        'fa-globe'                => 'Jordklode (fa-globe)',
        'fa-clock'                => 'Klokke (fa-clock)',
        'fa-calendar'             => 'Kalender (fa-calendar)',
        'fa-calendar-check'       => 'Kalender med hake (fa-calendar-check)',
        'fa-calendar-alt'         => 'Kalender (alt) (fa-calendar-alt)',
        'fa-hourglass-half'       => 'Timeglass (fa-hourglass-half)',
        'fa-history'              => 'Historikk (fa-history)',
        'fa-stopwatch'            => 'Stoppeklokke (fa-stopwatch)',

        // ── Utdanning & Kunnskap ─────────────────────────
        'fa-graduation-cap'       => 'Eksamenshatt (fa-graduation-cap)',
        'fa-book'                 => 'Bok (fa-book)',
        'fa-book-open'            => 'Åpen bok (fa-book-open)',
        'fa-university'           => 'Universitet (fa-university)',
        'fa-school'               => 'Skole (fa-school)',
        'fa-chalkboard-teacher'   => 'Lærer (fa-chalkboard-teacher)',
        'fa-user-graduate'        => 'Student (fa-user-graduate)',

        // ── Sikkerhet & Tillit ───────────────────────────
        'fa-shield-alt'           => 'Skjold (fa-shield-alt)',
        'fa-lock'                 => 'Lås (fa-lock)',
        'fa-certificate'          => 'Sertifikat (fa-certificate)',
        'fa-award'                => 'Pris / Utmerkelse (fa-award)',
        'fa-medal'                => 'Medalje (fa-medal)',
        'fa-trophy'               => 'Trofé (fa-trophy)',
        'fa-ribbon'               => 'Bånd (fa-ribbon)',
        'fa-star'                 => 'Stjerne (fa-star)',
        'fa-crown'                => 'Krone (fa-crown)',
        'fa-gem'                  => 'Edelstein (fa-gem)',

        // ── Status & Indikator ───────────────────────────
        'fa-check'                => 'Hake (fa-check)',
        'fa-check-circle'         => 'Hake i sirkel (fa-check-circle)',
        'fa-check-double'         => 'Dobbel hake (fa-check-double)',
        'fa-times'                => 'Kryss (fa-times)',
        'fa-times-circle'         => 'Kryss i sirkel (fa-times-circle)',
        'fa-plus'                 => 'Pluss (fa-plus)',
        'fa-plus-circle'          => 'Pluss i sirkel (fa-plus-circle)',
        'fa-minus'                => 'Minus (fa-minus)',
        'fa-info-circle'          => 'Info-sirkel (fa-info-circle)',
        'fa-question-circle'      => 'Spørsmålstegn (fa-question-circle)',
        'fa-exclamation-triangle'  => 'Advarsel-trekant (fa-exclamation-triangle)',
        'fa-exclamation-circle'   => 'Utropstegn i sirkel (fa-exclamation-circle)',
        'fa-bell'                 => 'Bjelle (fa-bell)',

        // ── Piler & Navigasjon ───────────────────────────
        'fa-arrow-down'           => 'Pil ned (fa-arrow-down)',
        'fa-arrow-up'             => 'Pil opp (fa-arrow-up)',
        'fa-arrow-right'          => 'Pil høyre (fa-arrow-right)',
        'fa-arrow-left'           => 'Pil venstre (fa-arrow-left)',
        'fa-chevron-down'         => 'Vinkel ned (fa-chevron-down)',
        'fa-chevron-right'        => 'Vinkel høyre (fa-chevron-right)',
        'fa-chevron-up'           => 'Vinkel opp (fa-chevron-up)',
        'fa-angle-double-right'   => 'Dobbelpil høyre (fa-angle-double-right)',
        'fa-external-link-alt'    => 'Ekstern lenke (fa-external-link-alt)',

        // ── Annet / Generelt ─────────────────────────────
        'fa-home'                 => 'Hus (fa-home)',
        'fa-cog'                  => 'Tannhjul (fa-cog)',
        'fa-cogs'                 => 'Tannhjul (flere) (fa-cogs)',
        'fa-wrench'               => 'Skiftenøkkel (fa-wrench)',
        'fa-tools'                => 'Verktøy (fa-tools)',
        'fa-lightbulb'            => 'Lyspære / Idé (fa-lightbulb)',
        'fa-link'                 => 'Lenke (fa-link)',
        'fa-thumbs-up'            => 'Tommel opp (fa-thumbs-up)',
        'fa-smile'                => 'Smilefjes (fa-smile)',
        'fa-smile-beam'           => 'Glad smilefjes (fa-smile-beam)',
        'fa-laugh'                => 'Latterfjes (fa-laugh)',
        'fa-meh'                  => 'Nøytralt fjes (fa-meh)',
        'fa-search'               => 'Søk / Lupe (fa-search)',
        'fa-eye'                  => 'Øye (fa-eye)',
        'fa-key'                  => 'Nøkkel (fa-key)',
        'fa-flag'                 => 'Flagg (fa-flag)',
        'fa-tags'                 => 'Merkelapper (fa-tags)',
        'fa-clipboard-list'       => 'Sjekkliste (fa-clipboard-list)',
        'fa-tasks'                => 'Oppgaver (fa-tasks)',
        'fa-list'                 => 'Liste (fa-list)',
        'fa-quote-left'           => 'Sitattegn (fa-quote-left)',
        'fa-paint-brush'          => 'Pensel (fa-paint-brush)',
        'fa-camera'               => 'Kamera (fa-camera)',
        'fa-video'                => 'Video (fa-video)',
        'fa-music'                => 'Musikk (fa-music)',
        'fa-coffee'               => 'Kaffe (fa-coffee)',
        'fa-utensils'             => 'Bestikk (fa-utensils)',
        'fa-pizza-slice'          => 'Pizza (fa-pizza-slice)',
        'fa-car'                  => 'Bil (fa-car)',
        'fa-bus'                  => 'Buss (fa-bus)',
        'fa-train'                => 'Tog (fa-train)',
        'fa-plane'                => 'Fly (fa-plane)',
        'fa-parking'              => 'Parkering (fa-parking)',
        'fa-recycle'              => 'Resirkulering (fa-recycle)',
        'fa-spa'                  => 'Spa / Velvære (fa-spa)',
        'fa-pray'                 => 'Meditasjon (fa-pray)',
        'fa-yin-yang'             => 'Yin-Yang (fa-yin-yang)',
        'fa-balance-scale'        => 'Vekt / Balanse (fa-balance-scale)',
    );
}
