<?php
/**
 * Front Page Template
 *
 * Single-page layout that includes all section partials in order.
 * This template is used when a static front page is set in WordPress.
 *
 * @package Lillestrom_Osteopati
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

get_header();

// Include all sections in order
get_template_part( 'template-parts/section', 'hero' );
get_template_part( 'template-parts/section', 'about' );
get_template_part( 'template-parts/section', 'osteopati' );
get_template_part( 'template-parts/section', 'behandlinger' );
get_template_part( 'template-parts/section', 'prosess' );
get_template_part( 'template-parts/section', 'behandlere' );
get_template_part( 'template-parts/section', 'forsikring' );
get_template_part( 'template-parts/section', 'bedrift' );
get_template_part( 'template-parts/section', 'priser' );
get_template_part( 'template-parts/section', 'kontakt' );
get_template_part( 'template-parts/section', 'faq' );
get_template_part( 'template-parts/section', 'timebestilling' );
get_template_part( 'template-parts/section', 'takk' );

get_footer();
