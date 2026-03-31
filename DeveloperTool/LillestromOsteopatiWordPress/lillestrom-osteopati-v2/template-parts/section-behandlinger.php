<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// Query treatment cards from CPT, fall back to hardcoded array if none exist.
$lo_treatments_query = new WP_Query( array(
    'post_type'      => 'behandling_type',
    'posts_per_page' => -1,
    'orderby'        => 'menu_order',
    'order'          => 'ASC',
    'post_status'    => 'publish',
) );

$lo_has_cpt_treatments = $lo_treatments_query->have_posts();

// Hardcoded fallback (used if no CPT posts exist yet).
$lo_fallback_treatments = array(
    array( 'icon' => 'fa-arrow-down',       'title' => 'Rygg- og nakkesmerter',    'description' => 'Akutte og langvarige smerter i rygg, nakke og korsrygg. Prolaps, isjias og stivhet.' ),
    array( 'icon' => 'fa-head-side-virus',  'title' => 'Hodepine og migrene',      'description' => 'Spenningshodepine, migrene og nakkerelatert hodepine som kan lindres med manuelle teknikker.' ),
    array( 'icon' => 'fa-running',          'title' => 'Idrettsskader',             'description' => 'Forstrekninger, senebetennelser, overbelastningsskader og rehabilitering etter skade.' ),
    array( 'icon' => 'fa-baby',             'title' => 'Barn og spedbarn',          'description' => 'Skånsomme teknikker for kolikk, urolige barn, skjevheter og ammeproblemer.' ),
    array( 'icon' => 'fa-female',           'title' => 'Graviditet',                'description' => 'Bekkensmerter, ryggsmerter og andre plager knyttet til svangerskap og fødsel.' ),
    array( 'icon' => 'fa-hand-paper',       'title' => 'Skulder, albue og hånd',    'description' => 'Frozen shoulder, tennisalbue, karpaltunnelsyndrom og andre plager i overekstremitetene.' ),
    array( 'icon' => 'fa-shoe-prints',      'title' => 'Kne, hofte og fot',         'description' => 'Artrose, løperkne, hælspore, plantarfasciitt og andre plager i underekstremitetene.' ),
    array( 'icon' => 'fa-couch',            'title' => 'Stivhet og nedsatt funksjon','description' => 'Generelt nedsatt bevegelighet, muskelstramhet og funksjonelle plager i hverdagen.' ),
    array( 'icon' => 'fa-stomach',          'title' => 'Mage- og fordøyelsesplager','description' => 'Funksjonelle mage-, tarm- og urinveisplager, sure oppstøt, halsbrann og fordøyelsesbesvær.' ),
    array( 'icon' => 'fa-wind',             'title' => 'Pustebesvær',               'description' => 'Tung pust og nedsatt pustefunksjon knyttet til stramhet i brystkasse og mellomgulv.' ),
    array( 'icon' => 'fa-laptop',           'title' => 'Kontorplager',              'description' => 'Belastningsskader og plager fra stillesittende arbeid, dårlig ergonomi og ensidig belastning.' ),
    array( 'icon' => 'fa-hand-sparkles',    'title' => 'Seneskjedebetennelser',     'description' => 'Betennelser i seneskjeder, overbelastningsskader og repetitive belastningsplager.' ),
);
?>

<section class="section section-light" id="behandlinger">
    <div class="container">
        <div class="section-header">
            <p class="section-label"><?php echo esc_html( lo_get_option( 'lo_behandlinger_label', 'Behandlinger' ) ); ?></p>
            <h2 class="section-title"><?php echo esc_html( lo_get_option( 'lo_behandlinger_title', 'Hva kan vi hjelpe deg med?' ) ); ?></h2>
            <p class="section-subtitle"><?php echo esc_html( lo_get_option( 'lo_behandlinger_subtitle', 'Osteopati kan hjelpe med et bredt spekter av plager. Her er noen av de vanligste tilstandene vi behandler.' ) ); ?></p>
        </div>
        <div class="treatments-grid">
            <?php if ( $lo_has_cpt_treatments ) : ?>
                <?php while ( $lo_treatments_query->have_posts() ) : $lo_treatments_query->the_post(); ?>
                    <?php $lo_icon = get_post_meta( get_the_ID(), '_behandling_icon', true ); ?>
                    <div class="treatment-card">
                        <i class="fas <?php echo esc_attr( $lo_icon ? $lo_icon : 'fa-hand-holding-medical' ); ?> treatment-icon"></i>
                        <h4><?php the_title(); ?></h4>
                        <p><?php echo esc_html( get_the_excerpt() ? get_the_excerpt() : wp_strip_all_tags( get_the_content() ) ); ?></p>
                    </div>
                <?php endwhile; ?>
                <?php wp_reset_postdata(); ?>
            <?php else : ?>
                <?php foreach ( $lo_fallback_treatments as $treatment ) : ?>
                    <div class="treatment-card">
                        <i class="fas <?php echo esc_attr( $treatment['icon'] ); ?> treatment-icon"></i>
                        <h4><?php echo esc_html( $treatment['title'] ); ?></h4>
                        <p><?php echo esc_html( $treatment['description'] ); ?></p>
                    </div>
                <?php endforeach; ?>
            <?php endif; ?>
        </div>
    </div>
</section>
