<?php
/**
 * Main Index Template (fallback)
 *
 * @package OnePager
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

get_header();

get_template_part( 'template-parts/section', 'hero' );
get_template_part( 'template-parts/section', 'about' );
get_template_part( 'template-parts/section', 'expertise' );
get_template_part( 'template-parts/section', 'services' );
get_template_part( 'template-parts/section', 'process' );
get_template_part( 'template-parts/section', 'team' );
get_template_part( 'template-parts/section', 'partners' );
get_template_part( 'template-parts/section', 'enterprise' );
get_template_part( 'template-parts/section', 'pricing' );
get_template_part( 'template-parts/section', 'contact' );
get_template_part( 'template-parts/section', 'faq' );
get_template_part( 'template-parts/section', 'cta' );
get_template_part( 'template-parts/section', 'thankyou' );

get_footer();
