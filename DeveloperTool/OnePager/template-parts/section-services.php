<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// Query service cards from CPT, fall back to hardcoded array if none exist.
$op_services_query = new WP_Query( array(
    'post_type'      => 'service_type',
    'posts_per_page' => -1,
    'orderby'        => 'menu_order',
    'order'          => 'ASC',
    'post_status'    => 'publish',
) );

$op_has_cpt_services = $op_services_query->have_posts();

// Hardcoded fallback (used if no CPT posts exist yet).
$op_fallback_services = array(
    array( 'icon' => 'fa-arrow-down',       'title' => 'Back & Neck Pain',       'description' => 'Acute and chronic pain in the back, neck and lower back. Disc issues, sciatica and stiffness.' ),
    array( 'icon' => 'fa-head-side-virus',  'title' => 'Headaches & Migraines',  'description' => 'Tension headaches, migraines and neck-related headaches that can be relieved with manual techniques.' ),
    array( 'icon' => 'fa-running',          'title' => 'Sports Injuries',         'description' => 'Sprains, tendinitis, overuse injuries and rehabilitation after injury.' ),
    array( 'icon' => 'fa-baby',             'title' => 'Children & Infants',      'description' => 'Gentle techniques for colic, restless children, asymmetries and feeding problems.' ),
    array( 'icon' => 'fa-female',           'title' => 'Pregnancy',               'description' => 'Pelvic pain, back pain and other complaints related to pregnancy and childbirth.' ),
    array( 'icon' => 'fa-hand-paper',       'title' => 'Shoulder, Elbow & Hand',  'description' => 'Frozen shoulder, tennis elbow, carpal tunnel syndrome and other upper extremity complaints.' ),
    array( 'icon' => 'fa-shoe-prints',      'title' => 'Knee, Hip & Foot',        'description' => 'Arthritis, runner\'s knee, heel spurs, plantar fasciitis and other lower extremity complaints.' ),
    array( 'icon' => 'fa-couch',            'title' => 'Stiffness & Reduced Function', 'description' => 'General reduced mobility, muscle tightness and functional complaints in daily life.' ),
    array( 'icon' => 'fa-stomach',          'title' => 'Digestive Complaints',    'description' => 'Functional stomach, intestinal and urinary complaints, acid reflux and digestive discomfort.' ),
    array( 'icon' => 'fa-wind',             'title' => 'Breathing Difficulties',  'description' => 'Heavy breathing and reduced respiratory function related to tightness in the chest and diaphragm.' ),
    array( 'icon' => 'fa-laptop',           'title' => 'Office-Related Pain',     'description' => 'Strain injuries and complaints from sedentary work, poor ergonomics and repetitive strain.' ),
    array( 'icon' => 'fa-hand-sparkles',    'title' => 'Tendon Inflammation',     'description' => 'Tendon sheath inflammation, overuse injuries and repetitive strain complaints.' ),
);
?>

<section class="section section-light" id="services">
    <div class="container">
        <div class="section-header">
            <p class="section-label"><?php echo esc_html( op_get_option( 'op_services_label', 'Services' ) ); ?></p>
            <h2 class="section-title"><?php echo esc_html( op_get_option( 'op_services_title', 'How can we help you?' ) ); ?></h2>
            <p class="section-subtitle"><?php echo esc_html( op_get_option( 'op_services_subtitle', 'We can help with a wide range of complaints. Here are some of the most common conditions we treat.' ) ); ?></p>
        </div>
        <div class="treatments-grid">
            <?php if ( $op_has_cpt_services ) : ?>
                <?php while ( $op_services_query->have_posts() ) : $op_services_query->the_post(); ?>
                    <?php $op_icon = get_post_meta( get_the_ID(), '_service_icon', true ); ?>
                    <div class="treatment-card">
                        <i class="fas <?php echo esc_attr( $op_icon ? $op_icon : 'fa-hand-holding-medical' ); ?> treatment-icon"></i>
                        <h4><?php the_title(); ?></h4>
                        <p><?php echo esc_html( get_the_excerpt() ? get_the_excerpt() : wp_strip_all_tags( get_the_content() ) ); ?></p>
                    </div>
                <?php endwhile; ?>
                <?php wp_reset_postdata(); ?>
            <?php else : ?>
                <?php foreach ( $op_fallback_services as $treatment ) : ?>
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
