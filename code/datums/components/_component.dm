/datum/component
	var/enabled = FALSE
	var/dupe_mode = COMPONENT_DUPE_HIGHLANDER
	var/dupe_type
	var/list/signal_procs
	var/datum/parent

/datum/component/New(datum/P, ...)
	parent = P
	var/list/arguments = args.Copy(2)
	if(Initialize(arglist(arguments)) == COMPONENT_INCOMPATIBLE)
		qdel(src, TRUE, TRUE)
		CRASH("Incompatible [type] assigned to a [P.type]!")

	_JoinParent(P)

/datum/component/proc/_JoinParent()
	var/datum/P = parent
	//lazy init the parent's dc list
	var/list/dc = P.datum_components
	if(!dc)
		P.datum_components = dc = list()

	//set up the typecache
	var/our_type = type
	for(var/I in _GetInverseTypeList(our_type))
		var/test = dc[I]
		if(test)	//already another component of this type here
			var/list/components_of_type
			if(!length(test))
				components_of_type = list(test)
				dc[I] = components_of_type
			else
				components_of_type = test
			if(I == our_type)	//exact match, take priority
				var/inserted = FALSE
				for(var/J in 1 to components_of_type.len)
					var/datum/component/C = components_of_type[J]
					if(C.type != our_type) //but not over other exact matches
						components_of_type.Insert(J, I)
						inserted = TRUE
						break
				if(!inserted)
					components_of_type += src
			else	//indirect match, back of the line with ya
				components_of_type += src
		else	//only component of this type, no list
			dc[I] = src

/datum/component/proc/Initialize(...)
	return

/datum/component/Destroy(force=FALSE, silent=FALSE)
	enabled = FALSE
	var/datum/P = parent
	if(!force)
		_RemoveFromParent()
	if(!silent)
		SEND_SIGNAL(P, COMSIG_COMPONENT_REMOVING, src)
	parent = null
	SSdcs.UnregisterSignal(src, signal_procs)
	LAZYCLEARLIST(signal_procs)
	return ..()

/datum/component/proc/_RemoveFromParent()
	var/datum/P = parent
	var/list/dc = P.datum_components
	for(var/I in _GetInverseTypeList())
		var/list/components_of_type = dc[I]
		if(length(components_of_type))	//
			var/list/subtracted = components_of_type - src
			if(subtracted.len == 1)	//only 1 guy left
				dc[I] = subtracted[1]	//make him special
			else
				dc[I] = subtracted
		else	//just us
			dc -= I
	if(!dc.len)
		P.datum_components = null

/datum/component/proc/RegisterSignal(sig_type_or_types, proc_or_callback, override = FALSE)
	if(QDELETED(src))
		return
	var/list/procs = signal_procs
	if(!procs)
		procs = list()
		signal_procs = procs

	if(!istype(proc_or_callback, /datum/callback)) //if it wasnt a callback before, it is now
		proc_or_callback = CALLBACK(src, proc_or_callback)

	var/list/sig_types = islist(sig_type_or_types) ? sig_type_or_types : list(sig_type_or_types)
	for(var/sig_type in sig_types)
		if(!override && procs[sig_type])
			stack_trace("[sig_type] overridden. Use override = TRUE to suppress this warning")

		if(sig_type[1] == "!")
			SSdcs.RegisterSignal(src, sig_type)
		
		procs[sig_type] = proc_or_callback

	enabled = TRUE

/datum/component/proc/HasSignal(sig_type)
	return signal_procs[sig_type] != null

/datum/component/proc/UnregisterSignal(sig_type_or_types)
	signal_procs -= sig_type_or_types

/datum/component/proc/InheritComponent(datum/component/C, i_am_original)
	return

/datum/component/proc/PreTransfer()
	return

/datum/component/proc/PostTransfer()
	return

/datum/component/proc/_GetInverseTypeList(our_type = type)
	//we can do this one simple trick
	var/current_type = parent_type
	. = list(our_type, current_type)
	//and since most components are root level + 1, this won't even have to run
	while (current_type != /datum/component)
		current_type = type2parent(current_type)
		. += current_type

/datum/proc/_SendSignal(sigtype, list/arguments)
	var/target = datum_components[/datum/component]
	if(!length(target))
		var/datum/component/C = target
		if(!C.enabled)
			return NONE
		var/datum/callback/CB = C.signal_procs[sigtype]
		if(!CB)
			return NONE
		return CB.InvokeAsync(arglist(arguments))
	. = NONE
	for(var/I in target)
		var/datum/component/C = I
		if(!C.enabled)
			continue
		var/datum/callback/CB = C.signal_procs[sigtype]
		if(!CB)
			continue
		. |= CB.InvokeAsync(arglist(arguments))

/datum/proc/GetComponent(c_type)
	var/list/dc = datum_components
	if(!dc)
		return null
	. = dc[c_type]
	if(length(.))
		return .[1]

/datum/proc/GetExactComponent(c_type)
	var/list/dc = datum_components
	if(!dc)
		return null
	var/datum/component/C = dc[c_type]
	if(C)
		if(length(C))
			C = C[1]
		if(C.type == c_type)
			return C
	return null

/datum/proc/GetComponents(c_type)
	var/list/dc = datum_components
	if(!dc)
		return null
	. = dc[c_type]
	if(!length(.))
		return list(.)

/datum/proc/AddComponent(new_type, ...)
	var/datum/component/nt = new_type
	var/dm = initial(nt.dupe_mode)
	var/dt = initial(nt.dupe_type)

	var/datum/component/old_comp
	var/datum/component/new_comp

	if(ispath(nt))
		if(nt == /datum/component)
			CRASH("[nt] attempted instantiation!")
		if(!isnum(dm))
			CRASH("[nt]: Invalid dupe_mode ([dm])!")
		if(dt && !ispath(dt))
			CRASH("[nt]: Invalid dupe_type ([dt])!")
	else
		new_comp = nt

	args[1] = src

	if(dm != COMPONENT_DUPE_ALLOWED)
		if(!dt)
			old_comp = GetExactComponent(nt)
		else
			old_comp = GetComponent(dt)
		if(old_comp)
			switch(dm)
				if(COMPONENT_DUPE_UNIQUE)
					if(!new_comp)
						new_comp = new nt(arglist(args))
					if(!QDELETED(new_comp))
						old_comp.InheritComponent(new_comp, TRUE)
						QDEL_NULL(new_comp)
				if(COMPONENT_DUPE_HIGHLANDER)
					if(!new_comp)
						new_comp = new nt(arglist(args))
					if(!QDELETED(new_comp))
						new_comp.InheritComponent(old_comp, FALSE)
						QDEL_NULL(old_comp)
				if(COMPONENT_DUPE_UNIQUE_PASSARGS)
					if(!new_comp)
						var/list/arguments = args.Copy(2)
						old_comp.InheritComponent(null, TRUE, arguments)
					else
						old_comp.InheritComponent(new_comp, TRUE)
		else if(!new_comp)
			new_comp = new nt(arglist(args)) // There's a valid dupe mode but there's no old component, act like normal
	else if(!new_comp)
		new_comp = new nt(arglist(args)) // Dupes are allowed, act like normal

	if(!old_comp && !QDELETED(new_comp)) // Nothing related to duplicate components happened and the new component is healthy
		SEND_SIGNAL(src, COMSIG_COMPONENT_ADDED, new_comp)
		return new_comp
	return old_comp

/datum/proc/LoadComponent(component_type, ...)
	. = GetComponent(component_type)
	if(!.)
		return AddComponent(arglist(args))

/datum/component/proc/RemoveComponent()
	if(!parent)
		return
	var/datum/old_parent = parent
	PreTransfer()
	_RemoveFromParent()
	SEND_SIGNAL(old_parent, COMSIG_COMPONENT_REMOVING, src)

/datum/proc/TakeComponent(datum/component/target)
	if(!target)
		return
	if(target.parent)
		target.RemoveComponent()
	target.parent = src
	if(target.PostTransfer() == COMPONENT_INCOMPATIBLE)
		var/c_type = target.type
		qdel(target)
		CRASH("Incompatible [c_type] transfer attempt to a [type]!")
	if(target == AddComponent(target))
		target._JoinParent()

/datum/proc/TransferComponents(datum/target)
	var/list/dc = datum_components
	if(!dc)
		return
	var/comps = dc[/datum/component]
	if(islist(comps))
		for(var/I in comps)
			target.TakeComponent(I)
	else
		target.TakeComponent(comps)

/datum/component/ui_host()
	return parent
