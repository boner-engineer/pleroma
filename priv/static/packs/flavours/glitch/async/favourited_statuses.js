(window.webpackJsonp=window.webpackJsonp||[]).push([[52],{672:function(t,e,a){"use strict";a.r(e),a.d(e,"default",function(){return R});var n,o,s,r=a(1),i=a(6),c=a(0),u=a(2),l=a(53),d=a.n(l),b=a(3),h=a.n(b),p=a(20),f=a(5),j=a.n(f),O=a(26),g=a.n(O),m=a(58),v=a(639),M=a(427),I=a(202),w=a(645),L=a(7),k=a(24),C=Object(L.f)({heading:{id:"column.favourites",defaultMessage:"Favourites"}}),R=Object(p.connect)(function(t){return{statusIds:t.getIn(["status_lists","favourites","items"]),isLoading:t.getIn(["status_lists","favourites","isLoading"],!0),hasMore:!!t.getIn(["status_lists","favourites","next"])}})(n=Object(L.g)((s=o=function(o){function t(){for(var n,t=arguments.length,e=new Array(t),a=0;a<t;a++)e[a]=arguments[a];return n=o.call.apply(o,[this].concat(e))||this,Object(u.a)(Object(c.a)(Object(c.a)(n)),"handlePin",function(){var t=n.props,e=t.columnId,a=t.dispatch;a(e?Object(I.h)(e):Object(I.e)("FAVOURITES",{}))}),Object(u.a)(Object(c.a)(Object(c.a)(n)),"handleMove",function(t){var e=n.props,a=e.columnId;(0,e.dispatch)(Object(I.g)(a,t))}),Object(u.a)(Object(c.a)(Object(c.a)(n)),"handleHeaderClick",function(){n.column.scrollTop()}),Object(u.a)(Object(c.a)(Object(c.a)(n)),"setRef",function(t){n.column=t}),Object(u.a)(Object(c.a)(Object(c.a)(n)),"handleLoadMore",d()(function(){n.props.dispatch(Object(m.g)())},300,{leading:!0})),n}Object(i.a)(t,o);var e=t.prototype;return e.componentWillMount=function(){this.props.dispatch(Object(m.h)())},e.render=function(){var t=this.props,e=t.intl,a=t.statusIds,n=t.columnId,o=t.multiColumn,s=t.hasMore,i=t.isLoading,c=!!n;return h.a.createElement(v.a,{ref:this.setRef,name:"favourites",label:e.formatMessage(C.heading)},Object(r.a)(M.a,{icon:"star",title:e.formatMessage(C.heading),onPin:this.handlePin,onMove:this.handleMove,onClick:this.handleHeaderClick,pinned:c,multiColumn:o,showBackButton:!0}),Object(r.a)(w.a,{trackScroll:!c,statusIds:a,scrollKey:"favourited_statuses-"+n,hasMore:s,isLoading:i,onLoadMore:this.handleLoadMore}))},t}(k.a),Object(u.a)(o,"propTypes",{dispatch:j.a.func.isRequired,statusIds:g.a.list.isRequired,intl:j.a.object.isRequired,columnId:j.a.string,multiColumn:j.a.bool,hasMore:j.a.bool,isLoading:j.a.bool}),n=s))||n)||n}}]);
//# sourceMappingURL=favourited_statuses.js.map