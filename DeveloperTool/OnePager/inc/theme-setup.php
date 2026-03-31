<?php
/**
 * Theme Setup — Initial Content Population
 *
 * Runs on theme activation (after_switch_theme) to auto-populate the site
 * with a static front page, primary navigation menu, sample team member posts,
 * FAQ items, service cards, and a Contact Form 7 contact form.
 *
 * Every section checks for existing content before creating anything,
 * making the routine safe to run more than once.
 *
 * @package OnePager
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit; // Prevent direct access.
}

add_action( 'after_switch_theme', 'op_populate_initial_content' );

/**
 * Populate the site with initial content on theme activation.
 */
function op_populate_initial_content() {

	/* ==================================================================
	 * 1. Create the "Home" page and set it as the static front page
	 * ================================================================ */

	op_setup_front_page();

	/* ==================================================================
	 * 2. Create the primary navigation menu "Main Menu"
	 * ================================================================ */

	op_setup_primary_menu();

	/* ==================================================================
	 * 3. Create initial Team Member (staff) posts
	 * ================================================================ */

	op_setup_team_member_posts();

	/* ==================================================================
	 * 4. Create initial FAQ posts
	 * ================================================================ */

	op_setup_faq_posts();

	/* ==================================================================
	 * 5. Create initial Service (service) cards
	 * ================================================================ */

	op_setup_service_posts();

	/* ==================================================================
	 * 6. Create Contact Form 7 form (if CF7 plugin is active)
	 * ================================================================ */

	op_setup_cf7_form();
}


/* --------------------------------------------------------------------------
 * 1. Static Front Page
 * ----------------------------------------------------------------------- */

/**
 * Create the "Home" page (if it doesn't exist) and configure it as the
 * static front page in WordPress reading settings.
 */
function op_setup_front_page() {

	// Check if a page with the slug "home" already exists.
	$existing = get_posts( array(
		'post_type'      => 'page',
		'name'           => 'home',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing ) ) {
		$page_id = $existing[0];
	} else {
		$page_id = wp_insert_post( array(
			'post_type'   => 'page',
			'post_title'  => 'Home',
			'post_name'   => 'home',
			'post_status' => 'publish',
		) );

		if ( is_wp_error( $page_id ) ) {
			return;
		}
	}

	// Set this page as the static front page.
	update_option( 'show_on_front', 'page' );
	update_option( 'page_on_front', $page_id );
}


/* --------------------------------------------------------------------------
 * 2. Primary Navigation Menu
 * ----------------------------------------------------------------------- */

/**
 * Create the "Main Menu" nav menu with anchor-link items and assign it
 * to the "primary" theme location.
 */
function op_setup_primary_menu() {

	$menu_name = 'Main Menu';

	// Check if the menu already exists.
	$menu_exists = wp_get_nav_menu_object( $menu_name );

	if ( $menu_exists ) {
		$menu_id = $menu_exists->term_id;
	} else {
		$menu_id = wp_create_nav_menu( $menu_name );

		if ( is_wp_error( $menu_id ) ) {
			return;
		}

		// Define menu items: label => fragment identifier.
		$menu_items = array(
			'Home'       => '#home',
			'About'      => '#about',
			'Expertise'  => '#expertise',
			'Services'   => '#services',
			'Team'       => '#team',
			'Partners'   => '#partners',
			'Enterprise' => '#enterprise',
			'Pricing'    => '#pricing',
			'FAQ'        => '#faq',
			'Contact'    => '#contact',
			'Get Started' => '#cta',
		);

		$position = 1;
		foreach ( $menu_items as $title => $fragment ) {
			wp_update_nav_menu_item( $menu_id, 0, array(
				'menu-item-title'   => $title,
				'menu-item-url'     => home_url( '/' ) . $fragment,
				'menu-item-status'  => 'publish',
				'menu-item-type'    => 'custom',
				'menu-item-position' => $position,
			) );
			$position++;
		}
	}

	// Assign the menu to the "primary" theme location.
	$locations            = get_theme_mod( 'nav_menu_locations', array() );
	$locations['primary'] = $menu_id;
	set_theme_mod( 'nav_menu_locations', $locations );
}


/* --------------------------------------------------------------------------
 * 3. Team Member (Staff) Posts
 * ----------------------------------------------------------------------- */

/**
 * Create the initial Team Member post for Jane Doe,
 * including custom meta fields, if no team member posts exist yet.
 */
function op_setup_team_member_posts() {

	// Only create if no team member posts exist.
	$existing = get_posts( array(
		'post_type'      => 'team_member',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing ) ) {
		return;
	}

	$bio  = 'Jane Doe is a seasoned professional with over a decade of experience in strategic consulting and business development. She specialises in helping organisations streamline operations, build high-performing teams, and achieve sustainable growth.' . "\n\n";
	$bio .= 'With a background spanning both the public and private sectors, Jane brings a unique perspective to every engagement. She is passionate about evidence-based approaches, continuous improvement, and empowering clients to reach their full potential.';

	$post_id = wp_insert_post( array(
		'post_type'    => 'team_member',
		'post_title'   => 'Jane Doe',
		'post_content' => $bio,
		'post_status'  => 'publish',
	) );

	if ( is_wp_error( $post_id ) ) {
		return;
	}

	// Professional title.
	update_post_meta( $post_id, '_team_member_title', 'Senior Consultant & Certified Professional' );

	// Credentials (one entry per line).
	$credentials  = "MBA — Harvard Business School\n";
	$credentials .= "Certified Management Consultant (CMC)\n";
	$credentials .= "Project Management Professional (PMP)\n";
	$credentials .= "Lean Six Sigma Black Belt\n";
	$credentials .= 'Certified Change Management Practitioner';
	update_post_meta( $post_id, '_team_member_credentials', $credentials );

	// Specialties (one entry per line).
	$specialties  = "Strategic planning and business development\n";
	$specialties .= "Organisational change management\n";
	$specialties .= "Process optimisation and operational efficiency\n";
	$specialties .= "Leadership coaching and team development\n";
	$specialties .= 'Stakeholder engagement and communication';
	update_post_meta( $post_id, '_team_member_specialties', $specialties );
}


/* --------------------------------------------------------------------------
 * 4. FAQ Posts
 * ----------------------------------------------------------------------- */

/**
 * Create the initial set of FAQ posts (faq_item CPT) if none exist yet.
 * Each FAQ uses the post title for the question and post content for the answer.
 * menu_order controls display ordering.
 */
function op_setup_faq_posts() {

	// Only create if no FAQ posts exist.
	$existing = get_posts( array(
		'post_type'      => 'faq_item',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing ) ) {
		return;
	}

	$faqs = array(
		array(
			'title'  => 'What services do you offer?',
			'answer' => 'We offer a comprehensive range of professional services including strategic planning, process optimisation, training and development, digital transformation, and ongoing support. Each engagement is tailored to your organisation\'s unique needs and goals.',
			'order'  => 1,
		),
		array(
			'title'  => 'How do I get started?',
			'answer' => 'Getting started is simple. Use our contact form or click "Get Started" to schedule a free initial consultation. During this session we will discuss your goals, assess your current situation, and outline a recommended approach.',
			'order'  => 2,
		),
		array(
			'title'  => 'What industries do you work with?',
			'answer' => 'We work with clients across a wide range of industries including technology, healthcare, finance, education, manufacturing, and non-profit. Our frameworks are adaptable and have been proven effective in diverse business environments.',
			'order'  => 3,
		),
		array(
			'title'  => 'How long does a typical engagement last?',
			'answer' => 'Engagement length varies depending on scope and complexity. A focused assessment may take 2–4 weeks, while a full transformation programme can span 3–12 months. We always provide a clear timeline and milestones at the outset.',
			'order'  => 4,
		),
		array(
			'title'  => 'Do you offer remote or on-site services?',
			'answer' => 'Yes, we offer both. Many of our services can be delivered remotely via video conferencing and collaboration tools. For hands-on workshops, training sessions, or larger programmes, we are happy to work on-site at your location.',
			'order'  => 5,
		),
		array(
			'title'  => 'What is your pricing model?',
			'answer' => 'We offer flexible pricing options including fixed-fee projects, retainer agreements, and hourly consulting. After our initial consultation we will provide a detailed proposal with transparent pricing tailored to your requirements.',
			'order'  => 6,
		),
		array(
			'title'  => 'Can you provide references or case studies?',
			'answer' => 'Absolutely. We are proud of our track record and happy to share relevant case studies and client testimonials. Please reach out and we will connect you with references in your industry.',
			'order'  => 7,
		),
		array(
			'title'  => 'What is your cancellation policy?',
			'answer' => 'We ask that cancellations or rescheduling requests be made at least 48 hours in advance. For ongoing retainer agreements, a 30-day written notice is required. Full details are outlined in our service agreement.',
			'order'  => 8,
		),
	);

	foreach ( $faqs as $faq ) {
		wp_insert_post( array(
			'post_type'    => 'faq_item',
			'post_title'   => $faq['title'],
			'post_content' => $faq['answer'],
			'post_status'  => 'publish',
			'menu_order'   => $faq['order'],
		) );
	}
}


/* --------------------------------------------------------------------------
 * 5. Service (Service) Cards
 * ----------------------------------------------------------------------- */

/**
 * Create the initial set of service cards (service_type CPT) if none exist yet.
 */
function op_setup_service_posts() {
	$existing = get_posts( array( 'post_type' => 'service_type', 'post_status' => 'any', 'posts_per_page' => 1, 'fields' => 'ids' ) );
	if ( ! empty( $existing ) ) {
		return;
	}

	$services = array(
		array( 'title' => 'Strategic Planning',        'desc' => 'Define your vision, set measurable goals, and build a roadmap to sustainable growth and competitive advantage.',             'icon' => 'fa-chess' ),
		array( 'title' => 'Process Optimisation',       'desc' => 'Streamline workflows, eliminate bottlenecks, and improve operational efficiency across your organisation.',                 'icon' => 'fa-cogs' ),
		array( 'title' => 'Training & Development',     'desc' => 'Upskill your team with tailored workshops, coaching programmes, and leadership development initiatives.',                  'icon' => 'fa-graduation-cap' ),
		array( 'title' => 'Digital Transformation',     'desc' => 'Leverage modern technology to automate processes, enhance customer experiences, and drive innovation.',                     'icon' => 'fa-laptop-code' ),
		array( 'title' => 'Change Management',          'desc' => 'Navigate organisational transitions smoothly with proven change frameworks, stakeholder engagement, and communication.',   'icon' => 'fa-exchange-alt' ),
		array( 'title' => 'Financial Advisory',         'desc' => 'Gain clarity on budgets, forecasts, and financial strategy to make confident, data-driven business decisions.',             'icon' => 'fa-chart-line' ),
		array( 'title' => 'Human Resources',            'desc' => 'Attract, retain, and develop top talent with modern HR practices, culture building, and performance management.',           'icon' => 'fa-users' ),
		array( 'title' => 'Marketing & Branding',       'desc' => 'Build a compelling brand identity and execute marketing strategies that resonate with your target audience.',                'icon' => 'fa-bullhorn' ),
		array( 'title' => 'Risk & Compliance',          'desc' => 'Identify, assess, and mitigate risks while ensuring full regulatory compliance across your operations.',                    'icon' => 'fa-shield-alt' ),
		array( 'title' => 'Customer Experience',        'desc' => 'Design and deliver exceptional customer journeys that increase satisfaction, loyalty, and lifetime value.',                 'icon' => 'fa-smile' ),
		array( 'title' => 'Data & Analytics',           'desc' => 'Turn raw data into actionable insights with dashboards, reporting frameworks, and predictive analytics.',                   'icon' => 'fa-chart-bar' ),
		array( 'title' => 'Sustainability & ESG',       'desc' => 'Integrate environmental, social, and governance principles into your strategy for long-term resilience and impact.',        'icon' => 'fa-leaf' ),
	);

	$order = 1;
	foreach ( $services as $s ) {
		$post_id = wp_insert_post( array(
			'post_type'    => 'service_type',
			'post_title'   => $s['title'],
			'post_content' => $s['desc'],
			'post_status'  => 'publish',
			'menu_order'   => $order,
		) );
		if ( ! is_wp_error( $post_id ) ) {
			update_post_meta( $post_id, '_service_icon', $s['icon'] );
		}
		$order++;
	}
}


/* --------------------------------------------------------------------------
 * 6. Contact Form 7 Form
 * ----------------------------------------------------------------------- */

/**
 * Create a Contact Form 7 form for the site if CF7 is active and no forms
 * exist yet. Stores the form ID as a theme mod for easy retrieval.
 */
function op_setup_cf7_form() {

	// Check if Contact Form 7 class is available (plugin must be active).
	if ( ! class_exists( 'WPCF7_ContactForm' ) ) {
		return;
	}

	// Check if a CF7 form already exists.
	$existing_forms = get_posts( array(
		'post_type'      => 'wpcf7_contact_form',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing_forms ) ) {
		return;
	}

	// Build the form markup.
	$form_template = '<div class="form-group">
<label>Name <span class="required">*</span></label>
[text* your-name placeholder "Your full name"]
</div>

<div class="form-group">
<label>Email <span class="required">*</span></label>
[email* your-email placeholder "you@example.com"]
</div>

<div class="form-group">
<label>Phone</label>
[tel your-phone placeholder "Optional"]
</div>

<div class="form-group">
<label>Message <span class="required">*</span></label>
[textarea* your-message placeholder "Briefly describe how we can help you..."]
</div>

[submit class:btn class:btn-primary class:btn-submit "Send Message"]';

	// Mail template.
	$mail_body  = "Name: [your-name]\n";
	$mail_body .= "Email: [your-email]\n";
	$mail_body .= "Phone: [your-phone]\n\n";
	$mail_body .= "Message:\n[your-message]";

	// Create the form using the CF7 API — wrapped in try/catch for safety.
	try {
		if ( ! method_exists( 'WPCF7_ContactForm', 'get_template' ) ) {
			return;
		}

		$contact_form = WPCF7_ContactForm::get_template();

		if ( ! $contact_form || ! is_object( $contact_form ) ) {
			return;
		}

		$contact_form->set_title( 'Contact Form' );

		$contact_form->set_properties( array(
			'form'             => $form_template,
			'mail'             => array(
				'active'             => true,
				'subject'            => 'New enquiry from the website — [your-name]',
				'sender'             => '[your-name] <[your-email]>',
				'recipient'          => 'hello@example.com',
				'body'               => $mail_body,
				'additional_headers' => 'Reply-To: [your-email]',
				'attachments'        => '',
				'use_html'           => false,
			),
			'mail_2'           => array(
				'active' => false,
			),
			'messages'         => array(),
			'additional_settings' => '',
		) );

		$form_id = $contact_form->save();

		if ( $form_id ) {
			// Store the form ID as a theme mod for easy access in templates.
			set_theme_mod( 'op_cf7_form_id', $form_id );
		}
	} catch ( Exception $e ) {
		// Silently fail — CF7 form can be created manually later.
		return;
	}
}
